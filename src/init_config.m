function cfg = init_config()
% INIT_CONFIG Inicjalizuje parametry fizyczne układu i ustawienia symulacji.
% Zwraca strukturę 'cfg' zoptymalizowaną pod kątem zużycia pamięci (typ single).

    %% 1. Ustawienia typów i precyzji (Optymalizacja RAM)
    % Globalna flaga typu danych do wykorzystania przy alokacji macierzy (np. zeros(..., cfg.dtype))
    cfg.dtype = 'single'; 

    %% 2. Parametry Źródła Światła
    % Długość fali dla lasera czerwonego, od razu rzutowana na single
    cfg.lambda = single(632.8e-9); 

    %% 3. Parametry Modulatora SLM
    cfg.Nx = uint16(3840); % Używamy uint16 dla wymiarów (zajmuje tylko 2 bajty)
    cfg.Ny = uint16(2160);
    cfg.pitch = single(3.74e-6); % Rozmiar piksela X i Y
    cfg.fill_factor = single(0.90);
    cfg.phase_levels = uint16(256); % 8-bitowa kwantyzacja fazy

    %% 4. Geometria Układu i Rekonstrukcji
    cfg.z_fresnel = single(0.5); % Odległość propagacji w bliskim polu [m]
    cfg.G = single(20.11); % Całkowite powiększenie układu optycznego
    
    % Efektywny rozmiar piksela (uwzględniający powiększenie układu)
    cfg.pitch_eff = cfg.pitch * cfg.G;

    %% 5. Parametry Obserwatora (Wyznaczanie Support Region)
    cfg.Dp = single(0.004); % Średnica źrenicy oka [m]
    cfg.Z_eye = single(0.33); % Odległość oka od okularu / wirtualnego obrazu [m]

end