CREATE TABLE IF NOT EXISTS categorii_varsta (
    id_categorie         SERIAL PRIMARY KEY,
    nume_categorie       VARCHAR(30) NOT NULL UNIQUE,
    specie               VARCHAR(50) NOT NULL,
    temp_min             NUMERIC(4,2) NOT NULL,
    temp_max             NUMERIC(4,2) NOT NULL,
    do_min_mg_l          NUMERIC(4,2) NOT NULL,
    ph_min               NUMERIC(4,2) NOT NULL,
    ph_max               NUMERIC(4,2) NOT NULL,
    debit_pompa_procent  INTEGER NOT NULL CHECK (debit_pompa_procent BETWEEN 20 AND 100),
    interval_hranire_min INTEGER NOT NULL,
    durata_dozare_ms     INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS bazine (
    id_bazin      SERIAL PRIMARY KEY,
    id_categorie  INTEGER NOT NULL REFERENCES categorii_varsta(id_categorie),
    nume_bazin    VARCHAR(60) NOT NULL,
    volum_m3      NUMERIC(6,2) NOT NULL,
    stare_activa  BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS masuratori_bazine (
    id_masuratoare  BIGSERIAL,
    id_bazin        INTEGER NOT NULL REFERENCES bazine(id_bazin),
    timestamp       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    temperatura_c   NUMERIC(5,2) NOT NULL,
    oxigen_do_mg_l  NUMERIC(5,2) NOT NULL,
    ph              NUMERIC(4,2) NOT NULL,
    turbiditate_ntu NUMERIC(6,2) NOT NULL,
    nivel_apa_cm    NUMERIC(6,2) NOT NULL,
    PRIMARY KEY (id_masuratoare, timestamp)
);

CREATE TABLE IF NOT EXISTS statie_filtrare_dunare (
    id_log_filtrare        BIGSERIAL PRIMARY KEY,
    timestamp              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    turbiditate_dunare_ntu NUMERIC(6,2) NOT NULL,
    turbiditate_iesire_ntu NUMERIC(6,2) NOT NULL,
    duritate_calcar_ppm    NUMERIC(6,2) NOT NULL,
    debit_recirculare_l_m  NUMERIC(7,2) NOT NULL,
    filtru_impuritati_ok   BOOLEAN NOT NULL,
    dozare_anticalcar_act  BOOLEAN NOT NULL,
    oxigenator_activ       BOOLEAN NOT NULL
);

CREATE TABLE IF NOT EXISTS evenimente_alarme (
    id_alarma        BIGSERIAL PRIMARY KEY,
    id_bazin         INTEGER REFERENCES bazine(id_bazin),
    timestamp        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    sursa_subsistem  VARCHAR(50) NOT NULL,
    tip_alarma       VARCHAR(80) NOT NULL,
    valoare_masurata NUMERIC(8,2),
    prag_depasit     NUMERIC(8,2),
    severitate       VARCHAR(20) NOT NULL CHECK (severitate IN ('INFO', 'WARNING', 'CRITICAL')),
    rezolvata        BOOLEAN NOT NULL DEFAULT FALSE
);

INSERT INTO categorii_varsta
    (nume_categorie, specie, temp_min, temp_max, do_min_mg_l, ph_min, ph_max, debit_pompa_procent, interval_hranire_min, durata_dozare_ms)
VALUES
    ('puiet',    'Pastrav / Sturion', 14.00, 16.00, 8.50, 6.80, 7.80, 55, 180, 1500),
    ('adulti',   'Pastrav / Sturion', 12.00, 15.00, 7.50, 6.50, 8.00, 85, 360, 3000),
    ('gestante', 'Pastrav / Sturion', 10.00, 13.00, 9.00, 7.00, 7.60, 65, 240, 2000)
ON CONFLICT (nume_categorie) DO NOTHING;

INSERT INTO bazine (id_bazin, id_categorie, nume_bazin, volum_m3, stare_activa)
VALUES
    (1, (SELECT id_categorie FROM categorii_varsta WHERE nume_categorie = 'puiet'),    'Bazin 1 - Puiet',    25.00, TRUE),
    (2, (SELECT id_categorie FROM categorii_varsta WHERE nume_categorie = 'adulti'),   'Bazin 2 - Adulti',   80.00, TRUE),
    (3, (SELECT id_categorie FROM categorii_varsta WHERE nume_categorie = 'gestante'), 'Bazin 3 - Gestante', 45.00, TRUE)
ON CONFLICT (id_bazin) DO NOTHING;
