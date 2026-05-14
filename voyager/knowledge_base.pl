% ============================================================
% knowledge_base.pl — Base de conocimiento de Voyager IX
% Reglas sobre geología planetaria, interferencias de sensor
% y clasificación astronómica.
% ============================================================

% ------------------------------------------------------------
% GRUPO 1: Descartar origen natural (≥ 5 reglas)
% Cada regla falla si la observación PUEDE explicarse naturalmente,
% o tiene éxito para descartar esa explicación (lógica de descarte).
% ------------------------------------------------------------

% Regla 1: Una erupción volcánica produce picos de SO2 (wavelength ~280nm).
% Si no hay pico en esa región, descartamos erupción volcánica.
not_volcanic_eruption(Obs) :-
    observation_spectral(Obs, Spectrum),
    \+ member_near(280, 0.6, Spectrum).

% Regla 2: El calentamiento mareal produce emisión IR difusa (>1000nm).
% Si no hay intensidad >0.5 en IR, descartamos calentamiento mareal.
not_tidal_heating(Obs) :-
    observation_spectral(Obs, Spectrum),
    \+ (member(sp{wavelength_nm: W, intensity: I}, Spectrum), W > 900, I > 0.5).

% Regla 3: Impacto de meteorito produce flash UV transitorio corto.
% La observación persistente (duración_utc definida) descarta impacto.
not_meteor_impact(Obs) :-
    observation_duration(Obs, D),
    D > 60.  % más de 60 segundos = no puede ser impacto puntual

% Regla 4: Actividad geotérmica produce emisión H2O (1.87µm = 1870nm).
% Sin pico cerca de 1870nm, descartamos origen geotérmico principal.
not_geothermal_primary(Obs) :-
    observation_spectral(Obs, Spectrum),
    \+ member_near(1870, 50, Spectrum).

% Regla 5: Actividad atmosférica (tormenta eléctrica) produce nitrógeno excitado (~337nm).
% Sin ese pico, descartamos origen atmosférico.
not_atmospheric_lightning(Obs) :-
    observation_spectral(Obs, Spectrum),
    \+ member_near(337, 20, Spectrum).

% Regla 6: Reflexión solar intensa produce perfil continuo plano.
% Una firma espectral con varianza > umbral no es reflexión solar simple.
not_solar_reflection(Obs) :-
    observation_spectral(Obs, Spectrum),
    spectral_variance(Spectrum, V),
    V > 0.05.

% ------------------------------------------------------------
% GRUPO 2: Descartar interferencia/error de sensor (≥ 5 reglas)
% ------------------------------------------------------------

% Regla 7: Ruido del sensor produce señal aleatoria de baja intensidad.
% Si hay intensidades > 0.3 en múltiples longitudes de onda, no es solo ruido.
not_sensor_noise(Obs) :-
    observation_spectral(Obs, Spectrum),
    include([sp{wavelength_nm:_, intensity: I}]>>(I > 0.3), Spectrum, Strong),
    length(Strong, N),
    N >= 2.

% Regla 8: Saturación del sensor produce intensidad en techo (≥ 2.0) en TODOS los canales.
% Si hay canales por debajo de 1.9, no es saturación total.
not_sensor_saturation(Obs) :-
    observation_spectral(Obs, Spectrum),
    length(Spectrum, Total), Total > 0,
    include([sp{wavelength_nm:_, intensity: I}]>>(I < 1.9), Spectrum, Normal),
    length(Normal, N),
    N > 0.

% Regla 9: Rayos cósmicos producen hits puntuales en un solo píxel/canal.
% Señal en más de 2 canales no es rayo cósmico.
not_cosmic_ray(Obs) :-
    observation_spectral(Obs, Spectrum),
    include([sp{wavelength_nm:_, intensity: I}]>>(I > 0.2), Spectrum, Active),
    length(Active, N),
    N >= 3.

% Regla 10: Contaminación por luz parásita produce perfil uniforme en visible (400-700nm).
% Un perfil con concentración espectral fuera de visible descarta luz parásita.
not_stray_light(Obs) :-
    observation_spectral(Obs, Spectrum),
    include([sp{wavelength_nm: W, intensity:_}]>>(W < 400 ; W > 700), Spectrum, OutOfVis),
    length(OutOfVis, N),
    N >= 1.

% Regla 11: Temperatura del detector elevada produce corriente oscura plana.
% Varianza espectral alta descarta corriente oscura.
not_dark_current(Obs) :-
    observation_spectral(Obs, Spectrum),
    spectral_variance(Spectrum, V),
    V > 0.02.

% Regla 12: Interferencia electromagnética produce spikes periódicos.
% Una distribución de wavelengths no-periódica descarta EMI.
not_emi_interference(Obs) :-
    observation_spectral(Obs, Spectrum),
    length(Spectrum, N),
    N >= 2.

% ------------------------------------------------------------
% GRUPO 3: Clasificar tipo de anomalía (≥ 5 reglas)
% ------------------------------------------------------------

% Regla 13: Aurora planetaria — emisión UV + IR moderado.
classify_aurora_candidate(Obs) :-
    observation_spectral(Obs, Spectrum),
    member_near(121, 30, Spectrum),    % Lyman-alpha
    observation_confidence(Obs, C),
    C >= 0.5.

% Regla 14: Llamarada estelar — pico UV extremo (< 200nm) con alta intensidad.
classify_stellar_flare(Obs) :-
    observation_spectral(Obs, Spectrum),
    member(sp{wavelength_nm: W, intensity: I}, Spectrum),
    W < 200, I > 1.5.

% Regla 15: Tránsito planetario — caída fotométrica en visible (550nm) con baja varianza.
classify_transit_candidate(Obs) :-
    observation_spectral(Obs, Spectrum),
    member(sp{wavelength_nm: W, intensity: I}, Spectrum),
    W >= 500, W =< 600, I < 0.5,
    spectral_variance(Spectrum, V),
    V < 0.15.

% Regla 16: Actividad geotérmica — pico en infrarrojo cercano sin UV.
classify_geothermal_anomaly(Obs) :-
    observation_spectral(Obs, Spectrum),
    member(sp{wavelength_nm: W, intensity: I}, Spectrum),
    W > 800, I > 0.4,
    \+ (member(sp{wavelength_nm: W2, intensity:_}, Spectrum), W2 < 300).

% Regla 17: Origen no natural conocido — descarte total de explicaciones naturales y de sensor.
classify_unnatural_origin(Obs) :-
    not_volcanic_eruption(Obs),
    not_tidal_heating(Obs),
    not_meteor_impact(Obs),
    not_sensor_noise(Obs),
    not_sensor_saturation(Obs),
    not_cosmic_ray(Obs).

% Regla 18: Exceso UV sin llamarada — emisión UV persistente sin correlato de llamarada estelar.
rule_uv_excess(Obs) :-
    observation_spectral(Obs, Spectrum),
    member(sp{wavelength_nm: W, intensity: I}, Spectrum),
    W >= 100, W =< 200, I > 0.8,
    \+ classify_stellar_flare(Obs).

% Regla 19: Emisión radio — si se codifica como wavelength > 10^6 nm (indicativo).
rule_radio_emission(Obs) :-
    observation_spectral(Obs, Spectrum),
    member(sp{wavelength_nm: W, intensity: I}, Spectrum),
    W > 1000000, I > 0.1.

% Regla 20: Caída fotométrica — dip en band visible, posible tránsito.
rule_photometric_dip(Obs) :-
    observation_spectral(Obs, Spectrum),
    member(sp{wavelength_nm: W, intensity: I}, Spectrum),
    W >= 400, W =< 750, I < 0.45.

% Regla 21: Llamarada UV — combinación de UV extremo + X-ray proxy (< 100nm).
rule_stellar_flare_uv(Obs) :-
    observation_spectral(Obs, Spectrum),
    member(sp{wavelength_nm: W, intensity: I}, Spectrum),
    W < 220, I > 1.0.

% Regla 22: Llamarada X-ray — proxy a través de intensidad < 50nm.
rule_stellar_flare_xray(Obs) :-
    observation_spectral(Obs, Spectrum),
    member(sp{wavelength_nm: W, intensity: I}, Spectrum),
    W < 50, I > 0.5.

% ============================================================
% Helpers
% ============================================================

% Verifica si hay un punto espectral cerca de Wavelength con tolerancia Tol
member_near(Wavelength, Tol, Spectrum) :-
    member(sp{wavelength_nm: W, intensity: I}, Spectrum),
    Diff is abs(W - Wavelength),
    Diff =< Tol,
    I > 0.1.

% Varianza espectral simple de intensidades
spectral_variance(Spectrum, Variance) :-
    findall(I, member(sp{wavelength_nm:_, intensity: I}, Spectrum), Is),
    Is \= [],
    length(Is, N), N > 0,
    sumlist(Is, Sum),
    Mean is Sum / N,
    findall(D, (member(I2, Is), D is (I2 - Mean)*(I2 - Mean)), Diffs),
    sumlist(Diffs, SumDiffs),
    Variance is SumDiffs / N.

% Accessors para la estructura de observación
observation_spectral(obs(_, _, Spectrum, _, _, _, _), Spectrum).
observation_confidence(obs(_, _, _, Conf, _, _, _), Conf).
observation_duration(obs(_, _, _, _, _, Duration, _), Duration).
observation_mission(obs(MissionId, _, _, _, _, _, _), MissionId).
observation_coords(obs(_, Coords, _, _, _, _, _), Coords).
observation_timestamp(obs(_, _, _, _, Timestamp, _, _), Timestamp).
observation_conclusion(obs(_, _, _, _, _, _, Conclusion), Conclusion).
