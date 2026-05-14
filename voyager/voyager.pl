% ============================================================
% voyager.pl — Voyager IX servidor TCP (puerto 7001)
% Acepta: OBSERVE (genera nueva observación) y QUERY_HISTORY
% ============================================================
:- use_module(library(socket)).
:- use_module(library(json)).
:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(aggregate)).

:- consult(knowledge_base).

% ============================================================
% Memoria dinámica de observaciones
% ============================================================
:- dynamic stored_observation/2.   % stored_observation(MissionId, JsonDict)
:- dynamic obs_counter/1.
obs_counter(0).

% ============================================================
% Entrada principal
% ============================================================
:- initialization(start_server, main).

start_server :-
    Port = 7001,
    now_iso(T),
    format("[VOYAGER ~w] Iniciando servidor TCP en puerto ~w~n", [T, Port]),
    tcp_socket(Socket),
    tcp_setopt(Socket, reuseaddr),
    tcp_bind(Socket, Port),
    tcp_listen(Socket, 5),
    accept_loop(Socket).

accept_loop(ServerSocket) :-
    tcp_accept(ServerSocket, ClientSocket, Peer),
    now_iso(T),
    format("[VOYAGER ~w] Conexion de ~w~n", [T, Peer]),
    flush_output,
    handle_client(ClientSocket),
    accept_loop(ServerSocket).

% ============================================================
% Manejo de conexiones
% ============================================================
handle_client(Socket) :-
    tcp_open_socket(Socket, In, Out),
    catch(
        ( read_line_to_string(In, Line),
          ( Line \= end_of_file ->
              handle_message(Line, Response),
              write(Out, Response),
              put_char(Out, '\n'),
              flush_output(Out)
          ; true )
        ),
        Error,
        ( now_iso(ET), format("[VOYAGER ~w] SOCKET ERROR: ~w~n", [ET, Error]), flush_output )
    ),
    close(In),
    close(Out).

% ============================================================
% Dispatcher de mensajes
% ============================================================
handle_message(Line, ResponseStr) :-
    catch(
        parse_and_dispatch(Line, ResponseStr),
        Error,
        ( term_to_atom(Error, EA),
          now_iso(ET),
          format(user_error, "[VOYAGER ~w] handle_message error: ~w~n", [ET, EA]),
          atom_string(EA, ES),
          string_concat("{\"error\":\"", ES, Tmp),
          string_concat(Tmp, "\"}", ResponseStr) )
    ).

parse_and_dispatch(Line, ResponseStr) :-
    open_string(Line, Stream),
    json_read_dict(Stream, MsgDict, []),
    dispatch(MsgDict, Response),
    with_output_to(string(ResponseStr),
        json_write_dict(current_output, Response, [width(0)])).

dispatch(MsgDict, Response) :-
    ( get_dict(type, MsgDict, MsgType),
      ( MsgType = "QUERY_HISTORY" ; MsgType = 'QUERY_HISTORY' ) ->
        handle_query_history(MsgDict, Response)
    ;
        handle_observe(MsgDict, Response)
    ).

% ============================================================
% OBSERVE — genera nueva observación
% ============================================================
handle_observe(_Msg, Response) :-
    generate_observation(Response),
    % Persistir en memoria
    get_dict(mission_id, Response, MissionId),
    retract(obs_counter(N)),
    N1 is N + 1,
    assert(obs_counter(N1)),
    assertz(stored_observation(MissionId, Response)),
    now_iso(T),
    format("[VOYAGER ~w] OBSERVE completado: mission=~w~n", [T, MissionId]).

% ============================================================
% QUERY_HISTORY — devuelve las últimas N observaciones
% ============================================================
handle_query_history(MsgDict, Response) :-
    ( get_dict(mission_id, MsgDict, MissionId0) -> true ; MissionId0 = "*" ),
    ( atom(MissionId0) -> atom_string(MissionId0, MissionId) ; MissionId = MissionId0 ),
    ( get_dict(limit, MsgDict, Limit) -> true ; Limit = 10 ),
    findall(O,
        ( stored_observation(Mid, O),
          ( MissionId = "*" -> true ; Mid = MissionId )
        ),
        AllObs),
    length(AllObs, Total),
    ( Total > Limit ->
        length(LastObs, Limit),
        append(_, LastObs, AllObs)
    ;
        LastObs = AllObs
    ),
    Response = json{
        type: "HISTORY_RESPONSE",
        mission_id: MissionId,
        total: Total,
        observations: LastObs
    }.

% ============================================================
% Generación de observación con inferencia por descarte
% ============================================================
generate_observation(Report) :-
    now_iso(Timestamp),
    MissionId = "VOY-IX-KEPLER442",

    % Espectro simulado con valores que provocan inferencia "no natural"
    Spectrum = [
        sp{wavelength_nm: 486,  intensity: 0.91},
        sp{wavelength_nm: 656,  intensity: 1.20},
        sp{wavelength_nm: 850,  intensity: 0.67},
        sp{wavelength_nm: 1100, intensity: 0.45}
    ],

    Coordinates = coords{
        right_ascension: "18h 52m 27.623s",
        declination: "+41° 51' 50.12\""
    },

    Confidence = 0.93,
    Duration   = 180,   % 3 minutos

    % Construir observación como término interno
    Obs = obs(MissionId, Coordinates, Spectrum, Confidence, Timestamp, Duration, ""),

    % ---- Inferencia por descarte ----
    run_inference(Obs, InferenceChain, Conclusion),

    % ---- Construir JSON report ----
    Report = json{
        mission_id:      MissionId,
        coordinates:     json{right_ascension: "18h 52m 27.623s",
                              declination:     "+41° 51' 50.12\""},
        spectral_reading: Spectrum,
        confidence:      Confidence,
        timestamp_utc:   Timestamp,
        inference_chain: InferenceChain,
        conclusion:      Conclusion,
        traceability_chain: [
            json{node: "VOYAGER_IX", timestamp_utc: Timestamp, action: "EMIT"}
        ]
    }.

% ============================================================
% Motor de inferencia por descarte
% ============================================================
run_inference(Obs, InferenceChain, Conclusion) :-
    % Fase 1: intentar explicación natural
    findall(RuleName, apply_natural_rule(Obs, RuleName), NaturalRules),
    % Fase 2: intentar explicación de sensor
    findall(RuleName, apply_sensor_rule(Obs, RuleName), SensorRules),
    % Fase 3: clasificar anomalía
    findall(RuleName, apply_classify_rule(Obs, RuleName), ClassifyRules),

    % Construir cadena de inferencia (list_to_set elimina duplicados de reglas con backtracking)
    append(NaturalRules, SensorRules, Chain1),
    append(Chain1, ClassifyRules, Chain2),
    list_to_set(Chain2, InferenceChain),

    % Determinar conclusión por descarte
    ( ClassifyRules = [] ->
        Conclusion = "observación no clasificada — datos insuficientes"
    ; member("classify_unnatural_origin", ClassifyRules) ->
        Conclusion = "origen no natural conocido"
    ; member("classify_stellar_flare", ClassifyRules) ->
        Conclusion = "llamarada estelar confirmada"
    ; member("classify_aurora_candidate", ClassifyRules) ->
        Conclusion = "aurora planetaria candidata"
    ; member("classify_transit_candidate", ClassifyRules) ->
        Conclusion = "tránsito planetario candidato"
    ; member("classify_geothermal_anomaly", ClassifyRules) ->
        Conclusion = "anomalía geotérmica"
    ;
        Conclusion = "anomalía clasificada"
    ).

% Reglas naturales que se aplican
apply_natural_rule(Obs, "not_volcanic_eruption") :-
    not_volcanic_eruption(Obs).
apply_natural_rule(Obs, "not_tidal_heating") :-
    not_tidal_heating(Obs).
apply_natural_rule(Obs, "not_meteor_impact") :-
    not_meteor_impact(Obs).
apply_natural_rule(Obs, "not_geothermal_primary") :-
    not_geothermal_primary(Obs).
apply_natural_rule(Obs, "not_atmospheric_lightning") :-
    not_atmospheric_lightning(Obs).
apply_natural_rule(Obs, "not_solar_reflection") :-
    not_solar_reflection(Obs).

% Reglas de sensor que se aplican
apply_sensor_rule(Obs, "not_sensor_noise") :-
    not_sensor_noise(Obs).
apply_sensor_rule(Obs, "not_sensor_saturation") :-
    not_sensor_saturation(Obs).
apply_sensor_rule(Obs, "not_cosmic_ray") :-
    not_cosmic_ray(Obs).
apply_sensor_rule(Obs, "not_stray_light") :-
    not_stray_light(Obs).
apply_sensor_rule(Obs, "not_dark_current") :-
    not_dark_current(Obs).
apply_sensor_rule(Obs, "not_emi_interference") :-
    not_emi_interference(Obs).

% Reglas de clasificación que se aplican
apply_classify_rule(Obs, "classify_unnatural_origin") :-
    classify_unnatural_origin(Obs).
apply_classify_rule(Obs, "classify_stellar_flare") :-
    classify_stellar_flare(Obs).
apply_classify_rule(Obs, "classify_aurora_candidate") :-
    classify_aurora_candidate(Obs).
apply_classify_rule(Obs, "classify_transit_candidate") :-
    classify_transit_candidate(Obs).
apply_classify_rule(Obs, "classify_geothermal_anomaly") :-
    classify_geothermal_anomaly(Obs).
apply_classify_rule(Obs, "rule_uv_excess") :-
    rule_uv_excess(Obs).
apply_classify_rule(Obs, "rule_photometric_dip") :-
    rule_photometric_dip(Obs).

% ============================================================
% Utilidades de tiempo
% ============================================================
now_iso(Timestamp) :-
    get_time(T),
    stamp_date_time(T, DT, 'UTC'),
    format_time(atom(Timestamp), '%Y-%m-%dT%H:%M:%SZ', DT).

now_str(S) :-
    now_iso(S).

