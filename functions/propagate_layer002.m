% Ścieżka do Twojego pliku (np. .pcd lub .ply)
filename = 'dragon_vrip.ply';

% Wczytanie chmury punktów do obiektu
ptCloud = pcread(filename);

% Wyciągnięcie współrzędnych przestrzennych (macierz N x 3)
xyz = ptCloud.Location;

% Wyciągnięcie wartości intensywności (wektor N x 1)
% Intensywność często wczytywana jest jako uint8 lub uint16.
intensity = ptCloud.Intensity;

% Sprawdzenie, czy plik faktycznie zawierał intensywność
if ~isempty(intensity)
    % Złączenie współrzędnych i intensywności w jedną macierz N x 4
    % Rzutujemy intensywność na 'double', aby typy danych w macierzy były spójne
    pointCloudMatrix = [single(xyz), single(intensity)];
    
    disp('Udało się! Utworzono macierz N x 4 (X, Y, Z, Intensywność).');
else
    disp('Uwaga: Ten plik chmury punktów nie zawiera informacji o intensywności.');
    % Jeśli brakuje intensywności, zostawiamy samo XYZ
    pointCloudMatrix = single(xyz);
end

ptCloud.Count

d_pointCloud = gpuArray(single(pointCloudMatrix));


%% Zoptymalizowane obliczanie hologramu (Wektoryzacja 3D / Mini-batching)
px = 3840; py = 2160;
pitch = 3.74e-6;
lambda = single(632.8e-9);
k = single(2 * pi / lambda);
N_holograms = 10;

x_vec = single(linspace(-px/2, px/2 - 1, px) * pitch);
y_vec = single(linspace(-py/2, py/2 - 1, py) * pitch);

[X, Y] = meshgrid(x_vec, y_vec);
X = gpuArray(single(X));
Y = gpuArray(single(Y));

random_phases = gpuArray.rand(py, px, N_holograms, 'single') * single(2 * pi);

% KRYTYCZNA ZMIANA: Zmniejszamy paczkę do 10-20 punktów!
% Tworzymy macierze w locie, aby nakarmić CUDA, ale nie wysadzić 8 GB VRAM.
chunk_size = 150;
num_points = size(d_pointCloud, 1);
base_hologram = complex(zeros(py, px, 'single', 'gpuArray'));

disp('Rozpoczęcie ekstremalnie równoległej generacji CGH na GPU...');

for i = 1:chunk_size:num_points
    idx = i:min(i+chunk_size-1, num_points);
    points = d_pointCloud(idx, :);
   
    % --- BRAK WEWNĘTRZNEJ PĘTLI ---
    % Używamy tzw. Broadcasting (niejawnej ekspansji macierzy).
    % Zmieniamy kształt wektorów punktów, by "wepchnąć" je w trzeci wymiar.
    px_coord = reshape(points(:, 1), 1, 1, []);
    py_coord = reshape(points(:, 2), 1, 1, []);
    pz_coord = reshape(points(:, 3), 1, 1, []);
   
   
    % 1. GPU oblicza dystanse dla całego bloku 20 punktów w jednym takcie zegara
    % Powstaje macierz 3D [2160 x 3840 x 20] ważąca ok. 660 MB - bezpiecznie mieści się w VRAM
    r_ij = sqrt((X - px_coord).^2 + (Y - py_coord).^2 + pz_coord.^2);
   
    % 2. Zastosowanie równania superpozycji zespolonej
    % Obliczamy falę dla tych 20 punktów i NATYCHMIAST je sumujemy redukując z powrotem do 2D
    % Uwalnia to VRAM, zanim przejdziemy do szumów fazowych.
    chunk_field = sum(exp(1i * k * r_ij), 3);
   
    % 3. Nakładamy N szumów fazowych w ramach multipleksowania czasowego
    base_hologram = base_hologram + chunk_field ;
end

hologram = base_hologram .* exp(1i * random_phases);
disp('Generacja zakończona.');
