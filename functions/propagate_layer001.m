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

%% obliczanie hologramu


% Parametry modulatora SLM Holoeye GAEA 2.0 (przykładowe wartości)
px = 3840; % rozdzielczość X
py = 2160; % rozdzielczość Y
pitch = 3.74e-6; % rozmiar piksela (w metrach)
lambda = single(632.8e-9); % długość fali - HeNe (rzutowanie na single)
k = single(2 * pi / lambda); % liczba falowa

N_holograms = 10; % Liczba hologramów do multipleksowania

% Generowanie wektorów współrzędnych przestrzennych dla CGH
x_vec = single(linspace(-px/2, px/2 - 1, px) * pitch);
y_vec = single(linspace(-py/2, py/2 - 1, py) * pitch);

% Przeniesienie siatki współrzędnych bezpośrednio na GPU
[X, Y] = meshgrid(x_vec, y_vec);
X = gpuArray(single(X));
Y = gpuArray(single(Y));

% Pre-alokacja macierzy losowych faz Z WYPRZEDZENIEM (nie w pętli!)
random_phases = gpuArray.rand(py, px, N_holograms, 'single') * single(2 * pi);

% Twoja wcześniejsza inicjalizacja (X, Y, random_phases, k, d_pointCloud) pozostaje bez zmian.

holograms

% Zmniejszamy paczkę do np. 50 punktów. Taka wielkość pozwoli
% na utworzenie macierzy [2160, 3840, 50] o wadze ok. 1.6 GB w VRAM.
mini_chunk_size = 50;
num_points = size(d_pointCloud, 1);

disp('Rozpoczęcie równoległej generacji CGH na GPU...');

% Pętla po mini-chunkach
for i = 1:mini_chunk_size:num_points
    idx = i:min(i+mini_chunk_size-1, num_points);
    points = d_pointCloud(idx, :); % Pobranie punktów
   
    % Wektoryzacja wymiaru trzeciego [1, 1, M]
    % Wypychamy współrzędne punktów w "głąb" (na trzeci wymiar macierzy)
    px_coord = reshape(points(:, 1), 1, 1, []);
    py_coord = reshape(points(:, 2), 1, 1, []);
    pz_coord = reshape(points(:, 3), 1, 1, []);
   
    % MATEMATYKA RÓWNOLEGŁA (GPU robi to w jednym takcie)
    % r_ij staje się macierzą o wymiarach: [2160, 3840, rozmiar_mini_chunka]
    r_ij = sqrt((X - px_coord).^2 + (Y - py_coord).^2 + pz_coord.^2);
   
    % Wyliczenie fali dla wszystkich 50 punktów naraz
    base_field_3d = exp(1i * k * r_ij);
   
    % Sumujemy wszystkie fale z wymiaru 3 (redukcja do płaskiej macierzy [2160, 3840])
    % Uwalniamy cenną pamięć na karcie graficznej
    summed_base_field = sum(base_field_3d, 3);
   
    % Na koniec: aplikacja unikalnych szumów fazowych na wektor 10 hologramów
    % Mnożenie (N_holograms) załatwia Broadcasting
    holograms = holograms + (summed_base_field .* exp(1i * random_phases));
end

disp('Generacja zakończona.');
