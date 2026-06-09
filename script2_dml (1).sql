-- =============================================================================
-- OutbreakNet Pandemic Surveillance System
-- Script 2: DML — Seed / Mock Data
-- Includes: 5 cities, 5 hospitals, 6 variants, 15 symptoms, 35 patients,
--           a complex 3-generation transmission tree, admissions, and daily stats
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. CITIES
-- -----------------------------------------------------------------------------
INSERT INTO Cities (city_name, province, population, area_sq_km, latitude, longitude) VALUES
    ('Lahore',     'Punjab',          14000000, 1772.00,  31.5204, 74.3587),
    ('Karachi',    'Sindh',           16000000, 3530.00,  24.8607, 67.0011),
    ('Islamabad',  'Federal Capital',  1200000,  906.00,  33.6844, 73.0479),
    ('Peshawar',   'KPK',              4200000,  1257.00,  34.0151, 71.5249),
    ('Quetta',     'Balochistan',      1400000,  2653.00,  30.1798, 66.9750);

-- -----------------------------------------------------------------------------
-- 2. HOSPITALS
-- -----------------------------------------------------------------------------
INSERT INTO Hospitals (hospital_name, city_id, address, total_beds, icu_beds_total, ventilators, is_designated_covid) VALUES
    ('Services Hospital Lahore',         1, 'Jail Road, Lahore',             850, 60, 40, TRUE),
    ('Jinnah Hospital Lahore',           1, 'Shad Bagh, Lahore',             700, 45, 30, TRUE),
    ('Aga Khan University Hospital',     2, 'Stadium Road, Karachi',         700, 80, 55, TRUE),
    ('PIMS Hospital',                    3, 'G-8/3, Islamabad',              600, 50, 35, TRUE),
    ('Hayatabad Medical Complex',        4, 'Hayatabad, Peshawar',           500, 40, 25, TRUE);

-- -----------------------------------------------------------------------------
-- 3. VARIANTS
-- -----------------------------------------------------------------------------
INSERT INTO Variants (variant_name, who_label, lineage, first_detected_date, origin_country, estimated_r0_min, estimated_r0_max, is_variant_of_concern, notes) VALUES
    ('Alpha',   'Alpha',   'B.1.1.7',     '2020-09-01', 'United Kingdom',  3.0, 5.0,  TRUE,  'First VOC — 50% more transmissible than wild-type'),
    ('Delta',   'Delta',   'B.1.617.2',   '2020-10-01', 'India',           5.0, 8.0,  TRUE,  'Dominant strain mid-2021; severe lung involvement'),
    ('Omicron', 'Omicron', 'B.1.1.529',   '2021-11-11', 'South Africa',    8.0, 15.0, TRUE,  'Highest R₀ observed; immune-evasive'),
    ('BA.2',    'Omicron', 'BA.2',        '2021-12-01', 'Multiple',        9.0, 16.0, TRUE,  'Omicron sub-variant with slight immune advantage'),
    ('XBB.1.5', 'Omicron', 'XBB.1.5',    '2022-10-01', 'USA',             10.0,17.0, TRUE,  'Kraken — high ACE2 binding affinity'),
    ('Wild',    NULL,      'B.0',         '2019-12-01', 'China',           2.0, 3.5,  FALSE, 'Original SARS-CoV-2 lineage');

-- -----------------------------------------------------------------------------
-- 4. SYMPTOMS
-- -----------------------------------------------------------------------------
INSERT INTO Symptoms (symptom_name, icd10_code, category, severity_weight, description) VALUES
    ('Fever',                 'R50.9',  'Systemic',      1.00, 'Oral temperature > 38°C'),
    ('Dry Cough',             'R05',    'Respiratory',   1.20, 'Non-productive persistent cough'),
    ('Fatigue',               'R53.83', 'Systemic',      0.80, 'Generalised weakness and tiredness'),
    ('Shortness of Breath',   'R06.0',  'Respiratory',   2.50, 'Dyspnoea at rest or on exertion'),
    ('Loss of Smell',         'R43.0',  'Neurological',  0.90, 'Anosmia — a hallmark of COVID-19'),
    ('Loss of Taste',         'R43.2',  'Neurological',  0.90, 'Ageusia — often accompanies anosmia'),
    ('Headache',              'R51',    'Neurological',  0.70, 'Frontoparietal pressure-type headache'),
    ('Body Aches',            'M79.3',  'Musculoskeletal',0.75,'Diffuse myalgia'),
    ('Sore Throat',           'J02.9',  'Respiratory',   0.60, 'Pharyngeal inflammation'),
    ('Diarrhoea',             'K59.1',  'Gastrointestinal',0.70,'≥3 loose stools per day'),
    ('Nausea',                'R11.0',  'Gastrointestinal',0.65,'Inclination to vomit'),
    ('Chest Pain',            'R07.9',  'Cardiovascular',2.00,'Substernal or pleuritic chest pain'),
    ('Confusion',             'R41.3',  'Neurological',  3.00, 'Acute encephalopathy / delirium'),
    ('Cyanosis',              'R23.0',  'Respiratory',   4.00, 'Peripheral or central blue discolouration'),
    ('Runny Nose',            'J06.9',  'Respiratory',   0.50, 'Rhinorrhoea — more common in Omicron');

-- -----------------------------------------------------------------------------
-- 5. PATIENTS  (35 patients across all cities)
--    Transmission tree legend (source → targets):
--      P1 (Patient Zero)
--        ├── P2
--        │     ├── P5
--        │     │     ├── P10
--        │     │     ├── P11
--        │     │     └── P12
--        │     ├── P6
--        │     │     ├── P13
--        │     │     └── P14
--        │     └── P7
--        ├── P3
--        │     ├── P8
--        │     │     ├── P15
--        │     │     ├── P16
--        │     │     └── P17
--        │     └── P9
--        │           ├── P18
--        │           └── P19
--        └── P4
--              ├── P20
--              │     ├── P25
--              │     ├── P26
--              │     └── P27
--              ├── P21
--              │     ├── P28
--              │     └── P29
--              ├── P22
--              ├── P23
--              └── P24
--                    ├── P30
--                    ├── P31
--                    ├── P32
--                    ├── P33
--                    ├── P34
--                    └── P35
-- -----------------------------------------------------------------------------

INSERT INTO Patients
    (national_id, first_name, last_name, date_of_birth, gender, city_id,
     diagnosis_date, variant_id, current_status, is_vaccinated, vaccination_doses,
     comorbidities, blood_type, phone) VALUES

-- Generation 0  (Patient Zero — index case)
('3520112345001','Ahmed',   'Khan',      '1975-03-15','M',1,'2024-01-05',3,'Recovered',TRUE, 2,ARRAY['Hypertension'],'A+','0300-1111001'),

-- Generation 1  (direct from P1)
('3520112345002','Fatima',  'Malik',     '1982-07-22','F',1,'2024-01-08',3,'Recovered',TRUE, 2,NULL,'B+','0300-1111002'),
('3520112345003','Bilal',   'Hassan',    '1990-11-10','M',2,'2024-01-09',3,'Recovered',FALSE,0,ARRAY['Diabetes'],'O+','0300-1111003'),
('3520112345004','Zara',    'Qureshi',   '1988-05-30','F',1,'2024-01-10',3,'Active',  TRUE, 1,NULL,'AB+','0300-1111004'),

-- Generation 2  (from P2)
('3520112345005','Usman',   'Raza',      '1995-02-18','M',1,'2024-01-12',3,'Recovered',TRUE, 2,NULL,'A-','0300-1111005'),
('3520112345006','Aisha',   'Nawaz',     '1978-09-05','F',1,'2024-01-13',3,'Recovered',FALSE,0,ARRAY['Asthma'],'B-','0300-1111006'),
('3520112345007','Imran',   'Shah',      '2001-04-25','M',1,'2024-01-14',3,'Active',  TRUE, 1,NULL,'O-','0300-1111007'),

-- Generation 2  (from P3)
('3520112345008','Sana',    'Ali',       '1985-12-01','F',2,'2024-01-11',3,'Deceased',FALSE,0,ARRAY['Diabetes','Hypertension'],'A+','0300-1111008'),
('3520112345009','Tariq',   'Butt',      '1970-06-14','M',2,'2024-01-12',3,'Recovered',TRUE, 2,ARRAY['Cardiac Disease'],'AB-','0300-1111009'),

-- Generation 2  (from P4)
('3520112345010','Nadia',   'Hussain',   '1993-08-20','F',3,'2024-01-13',4,'Recovered',TRUE, 2,NULL,'B+','0300-1111010'),
('3520112345011','Kamran',  'Iqbal',     '1987-01-17','M',3,'2024-01-14',4,'Recovered',FALSE,0,NULL,'O+','0300-1111011'),
('3520112345012','Hira',    'Chaudhry',  '1999-03-03','F',1,'2024-01-14',4,'Active',  TRUE, 1,NULL,'A+','0300-1111012'),

-- Generation 3  (from P5)
('3520112345013','Omar',    'Farooq',    '2000-07-07','M',1,'2024-01-16',3,'Recovered',TRUE, 2,NULL,'B-','0300-1111013'),
('3520112345014','Maham',   'Yousaf',    '1992-10-29','F',1,'2024-01-17',3,'Active',  FALSE,0,ARRAY['Obesity'],'O+','0300-1111014'),

-- Generation 3  (from P6)
('3520112345015','Faisal',  'Sheikh',    '1980-04-11','M',2,'2024-01-15',3,'Deceased',FALSE,0,ARRAY['Hypertension','Cardiac Disease'],'A-','0300-1111015'),
('3520112345016','Amna',    'Siddiqui',  '2003-11-22','F',2,'2024-01-16',3,'Recovered',TRUE, 1,NULL,'AB+','0300-1111016'),
('3520112345017','Rehman',  'Anwer',     '1997-06-30','M',2,'2024-01-17',3,'Active',  TRUE, 2,NULL,'B+','0300-1111017'),

-- Generation 3  (from P7)
('3520112345018','Sundas',  'Mirza',     '1986-02-14','F',4,'2024-01-15',2,'Recovered',FALSE,0,NULL,'O-','0300-1111018'),
('3520112345019','Junaid',  'Bajwa',     '1994-09-09','M',4,'2024-01-16',2,'Active',  TRUE, 1,ARRAY['Diabetes'],'A+','0300-1111019'),

-- Generation 3  (from P8)
('3520112345020','Saima',   'Riaz',      '1977-05-25','F',2,'2024-01-14',3,'Recovered',TRUE, 2,NULL,'B+','0300-1111020'),
('3520112345021','Waseem',  'Latif',     '1983-12-18','M',2,'2024-01-15',3,'Recovered',FALSE,0,ARRAY['Asthma'],'O+','0300-1111021'),
('3520112345022','Komal',   'Akram',     '2002-08-04','F',2,'2024-01-16',3,'Active',  TRUE, 1,NULL,'A+','0300-1111022'),

-- Generation 3  (from P9)
('3520112345023','Shahzad', 'Gondal',    '1968-03-28','M',1,'2024-01-14',4,'Recovered',TRUE, 2,ARRAY['Diabetes','COPD'],'AB+','0300-1111023'),
('3520112345024','Rabia',   'Niazi',     '1998-07-15','F',1,'2024-01-15',4,'Active',  FALSE,0,NULL,'O+','0300-1111024'),

-- Generation 3  (from P20 in the P4 branch)
('3520112345025','Hassan',  'Javed',     '1991-01-31','M',3,'2024-01-17',4,'Recovered',TRUE, 2,NULL,'B-','0300-1111025'),
('3520112345026','Maryam',  'Zahid',     '2004-06-06','F',3,'2024-01-18',4,'Active',  TRUE, 1,NULL,'A+','0300-1111026'),
('3520112345027','Asad',    'Awan',      '1989-10-10','M',3,'2024-01-18',4,'Recovered',FALSE,0,NULL,'O-','0300-1111027'),

-- Generation 3  (from P21 in the P4 branch)
('3520112345028','Noor',    'Bhatti',    '1996-04-19','F',1,'2024-01-18',3,'Active',  TRUE, 2,NULL,'A-','0300-1111028'),
('3520112345029','Aamir',   'Satti',     '1974-11-08','M',5,'2024-01-19',3,'Recovered',FALSE,0,ARRAY['Hypertension'],'B+','0300-1111029'),

-- Generation 4  (from P24 — deepest branch, showcases 4-hop tracing)
('3520112345030','Lubna',   'Butt',      '2005-02-23','F',1,'2024-01-20',3,'Active',  TRUE, 1,NULL,'AB+','0300-1111030'),
('3520112345031','Danyal',  'Rizvi',     '1993-07-07','M',1,'2024-01-20',3,'Recovered',TRUE, 2,NULL,'O+','0300-1111031'),
('3520112345032','Zainab',  'Channa',    '1988-09-14','F',2,'2024-01-21',3,'Active',  FALSE,0,ARRAY['Obesity'],'A+','0300-1111032'),
('3520112345033','Talha',   'Sohail',    '2000-03-11','M',2,'2024-01-21',3,'Recovered',TRUE, 1,NULL,'B+','0300-1111033'),
('3520112345034','Rida',    'Gillani',   '1979-12-02','F',4,'2024-01-22',2,'Recovered',TRUE, 2,ARRAY['Diabetes'],'O-','0300-1111034'),
('3520112345035','Muneeb',  'Durrani',   '1985-08-27','M',5,'2024-01-22',3,'Active',  FALSE,0,NULL,'AB-','0300-1111035');

-- -----------------------------------------------------------------------------
-- 6. PATIENT_SYMPTOMS
-- -----------------------------------------------------------------------------
INSERT INTO Patient_Symptoms (patient_id, symptom_id, onset_date, resolution_date, severity) VALUES
-- P1 (Ahmed Khan)
(1,1,'2024-01-05','2024-01-12','Moderate'),(1,2,'2024-01-05','2024-01-14','Moderate'),(1,5,'2024-01-06','2024-01-18','Mild'),
-- P2 (Fatima Malik)
(2,1,'2024-01-08','2024-01-15','Mild'),(2,3,'2024-01-08','2024-01-16','Mild'),(2,15,'2024-01-09',NULL,'Mild'),
-- P3 (Bilal Hassan)
(3,1,'2024-01-09','2024-01-16','Moderate'),(3,4,'2024-01-10','2024-01-17','Severe'),(3,12,'2024-01-11',NULL,'Moderate'),
-- P4 (Zara Qureshi)
(4,1,'2024-01-10',NULL,'Mild'),(4,7,'2024-01-10',NULL,'Mild'),(4,9,'2024-01-11',NULL,'Mild'),
-- P5 (Usman Raza)
(5,1,'2024-01-12','2024-01-19','Mild'),(5,2,'2024-01-12','2024-01-20','Mild'),(5,5,'2024-01-13','2024-01-21','Mild'),
-- P6 (Aisha Nawaz)
(6,4,'2024-01-13','2024-01-22','Severe'),(6,12,'2024-01-14','2024-01-25','Severe'),(6,1,'2024-01-13','2024-01-22','Moderate'),
-- P8 (Sana Ali — Deceased)
(8,4,'2024-01-11',NULL,'Critical'),(8,13,'2024-01-12',NULL,'Critical'),(8,14,'2024-01-13',NULL,'Critical'),(8,12,'2024-01-11',NULL,'Critical'),
-- P9 (Tariq Butt)
(9,1,'2024-01-12','2024-01-20','Moderate'),(9,4,'2024-01-13','2024-01-22','Severe'),(9,3,'2024-01-12','2024-01-19','Moderate'),
-- P15 (Faisal Sheikh — Deceased)
(15,4,'2024-01-15',NULL,'Critical'),(15,12,'2024-01-16',NULL,'Critical'),(15,13,'2024-01-17',NULL,'Critical'),
-- Remaining patients — lighter symptom sets
(10,1,'2024-01-13','2024-01-20','Mild'),(10,7,'2024-01-13','2024-01-18','Mild'),
(11,1,'2024-01-14','2024-01-21','Mild'),(11,15,'2024-01-14','2024-01-19','Mild'),
(12,1,'2024-01-14',NULL,'Moderate'),(12,4,'2024-01-15',NULL,'Moderate'),
(13,1,'2024-01-16','2024-01-23','Mild'),(13,6,'2024-01-16','2024-01-23','Mild'),
(14,1,'2024-01-17',NULL,'Mild'),(14,3,'2024-01-17',NULL,'Mild'),
(16,1,'2024-01-16','2024-01-22','Mild'),(16,9,'2024-01-16','2024-01-20','Mild'),
(17,1,'2024-01-17',NULL,'Mild'),(17,2,'2024-01-17',NULL,'Mild'),
(18,1,'2024-01-15','2024-01-22','Moderate'),(18,8,'2024-01-15','2024-01-20','Mild'),
(19,1,'2024-01-16',NULL,'Mild'),(19,10,'2024-01-16',NULL,'Mild'),
(20,1,'2024-01-14','2024-01-21','Mild'),(20,5,'2024-01-14','2024-01-22','Mild'),
(21,2,'2024-01-15','2024-01-23','Moderate'),(21,4,'2024-01-16','2024-01-25','Severe'),
(22,1,'2024-01-16',NULL,'Mild'),(22,7,'2024-01-16',NULL,'Mild'),
(23,1,'2024-01-14','2024-01-21','Mild'),(23,6,'2024-01-14','2024-01-21','Mild'),
(24,1,'2024-01-15',NULL,'Moderate'),(24,4,'2024-01-16',NULL,'Moderate'),
(25,1,'2024-01-17','2024-01-24','Mild'),(26,1,'2024-01-18',NULL,'Mild'),
(27,1,'2024-01-18','2024-01-25','Mild'),(28,1,'2024-01-18',NULL,'Mild'),
(29,1,'2024-01-19','2024-01-26','Moderate'),(29,12,'2024-01-20','2024-01-27','Moderate'),
(30,1,'2024-01-20',NULL,'Mild'),(31,1,'2024-01-20','2024-01-27','Mild'),
(32,1,'2024-01-21',NULL,'Moderate'),(33,1,'2024-01-21','2024-01-28','Mild'),
(34,1,'2024-01-22','2024-01-29','Mild'),(35,1,'2024-01-22',NULL,'Mild');

-- -----------------------------------------------------------------------------
-- 7. HOSPITAL_ADMISSIONS
-- -----------------------------------------------------------------------------
INSERT INTO Hospital_Admissions
    (patient_id, hospital_id, admission_date, discharge_date, admission_status, ward, severity_on_entry) VALUES
(1,  1, '2024-01-06', '2024-01-18', 'Discharged', 'Isolation',  'Moderate'),
(2,  1, '2024-01-09', '2024-01-20', 'Discharged', 'General',    'Mild'),
(3,  3, '2024-01-10', '2024-01-22', 'Discharged', 'Isolation',  'Moderate'),
(4,  1, '2024-01-11', NULL,         'Admitted',   'Isolation',  'Mild'),
(5,  1, '2024-01-13', '2024-01-24', 'Discharged', 'General',    'Mild'),
(6,  1, '2024-01-14', '2024-01-27', 'Discharged', 'ICU',        'Severe'),
(8,  3, '2024-01-12', '2024-01-20', 'Deceased',   'ICU',        'Critical'),
(9,  3, '2024-01-13', '2024-01-25', 'Discharged', 'ICU',        'Severe'),
(12, 1, '2024-01-15', NULL,         'ICU',        'ICU',        'Severe'),
(15, 3, '2024-01-16', '2024-01-23', 'Deceased',   'ICU',        'Critical'),
(17, 3, '2024-01-18', NULL,         'Admitted',   'Isolation',  'Mild'),
(19, 5, '2024-01-17', NULL,         'Admitted',   'General',    'Mild'),
(21, 3, '2024-01-16', '2024-01-28', 'Discharged', 'ICU',        'Severe'),
(23, 1, '2024-01-15', '2024-01-23', 'Discharged', 'General',    'Mild'),
(24, 1, '2024-01-16', NULL,         'Admitted',   'Isolation',  'Moderate'),
(29, 4, '2024-01-20', '2024-01-29', 'Discharged', 'General',    'Moderate'),
(32, 3, '2024-01-22', NULL,         'Admitted',   'Isolation',  'Moderate'),
(35, 4, '2024-01-23', NULL,         'Admitted',   'General',    'Mild');

-- Manually set ICU occupancy to reflect current ICU admissions
-- (Triggers will maintain this going forward; this is the initial state seed)
UPDATE Hospitals SET icu_bed_occupancy = 2 WHERE hospital_id = 1;  -- P6 (done), P12 (active ICU)
UPDATE Hospitals SET icu_bed_occupancy = 1 WHERE hospital_id = 3;  -- P9 (done), P21 (done), current: 0 net — but P17 admitted
-- Realistic initial occupancy counts (pre-trigger state)
UPDATE Hospitals SET icu_bed_occupancy = 3 WHERE hospital_id = 1;
UPDATE Hospitals SET icu_bed_occupancy = 2 WHERE hospital_id = 3;
UPDATE Hospitals SET icu_bed_occupancy = 1 WHERE hospital_id = 4;

-- -----------------------------------------------------------------------------
-- 8. TRANSMISSION_CHAIN
--    NULL source_patient_id = Patient Zero (P1 has no recorded source)
-- -----------------------------------------------------------------------------
INSERT INTO Transmission_Chain
    (source_patient_id, target_patient_id, transmission_date, transmission_mode,
     location_of_event, city_id, confidence_score, contact_duration_hrs, is_confirmed) VALUES

-- Root node: P1 has unknown origin
(NULL, 1,  '2024-01-05', 'Unknown',        'International Airport Lahore', 1, 0.950, NULL,  TRUE),

-- Generation 1
(1,   2,  '2024-01-08', 'Direct_Contact', 'Family Home, Gulberg Lahore',  1, 0.990, 48.0,  TRUE),
(1,   3,  '2024-01-09', 'Airborne',       'Office Building, Karachi',     2, 0.880, 8.0,   TRUE),
(1,   4,  '2024-01-10', 'Direct_Contact', 'Family Home, Gulberg Lahore',  1, 0.975, 72.0,  TRUE),

-- Generation 2 — from P2
(2,   5,  '2024-01-12', 'Direct_Contact', 'Workplace, Model Town Lahore', 1, 0.920, 6.0,   TRUE),
(2,   6,  '2024-01-13', 'Airborne',       'Shopping Mall, Lahore',        1, 0.750, 2.0,   TRUE),
(2,   7,  '2024-01-14', 'Direct_Contact', 'University Campus, Lahore',    1, 0.860, 4.0,   TRUE),

-- Generation 2 — from P3
(3,   8,  '2024-01-11', 'Direct_Contact', 'Family Home, Karachi',         2, 0.995, 96.0,  TRUE),
(3,   9,  '2024-01-12', 'Direct_Contact', 'Community Gathering, Karachi', 2, 0.880, 12.0,  TRUE),

-- Generation 2 — from P4
(4,   20, '2024-01-14', 'Airborne',       'Hospital Corridor, Islamabad', 3, 0.820, 1.5,   TRUE),
(4,   21, '2024-01-15', 'Direct_Contact', 'Wedding Hall, Islamabad',      3, 0.900, 6.0,   TRUE),
(4,   22, '2024-01-16', 'Airborne',       'Wedding Hall, Islamabad',      3, 0.780, 6.0,   TRUE),
(4,   23, '2024-01-16', 'Direct_Contact', 'Family Home, Lahore',          1, 0.960, 24.0,  TRUE),
(4,   24, '2024-01-17', 'Direct_Contact', 'Family Home, Lahore',          1, 0.965, 48.0,  TRUE),

-- Generation 3 — from P5
(5,   10, '2024-01-16', 'Airborne',       'Office, Islamabad',            3, 0.800, 4.0,   TRUE),
(5,   11, '2024-01-17', 'Direct_Contact', 'School, Islamabad',            3, 0.870, 8.0,   TRUE),
(5,   12, '2024-01-17', 'Fomite',         'Gym, Lahore',                  1, 0.650, 1.0,   TRUE),

-- Generation 3 — from P6
(6,   13, '2024-01-16', 'Airborne',       'Mosque, Lahore',               1, 0.820, 1.0,   TRUE),
(6,   14, '2024-01-17', 'Direct_Contact', 'Workplace, Lahore',            1, 0.780, 6.0,   TRUE),

-- Generation 3 — from P8
(8,   15, '2024-01-15', 'Direct_Contact', 'Family Home, Karachi',         2, 0.990, 120.0, TRUE),
(8,   16, '2024-01-16', 'Airborne',       'Family Home, Karachi',         2, 0.940, 48.0,  TRUE),
(8,   17, '2024-01-17', 'Direct_Contact', 'Family Home, Karachi',         2, 0.950, 48.0,  TRUE),

-- Generation 3 — from P9
(9,   18, '2024-01-15', 'Airborne',       'Community Hall, Peshawar',     4, 0.760, 3.0,   TRUE),
(9,   19, '2024-01-16', 'Direct_Contact', 'Restaurant, Peshawar',         4, 0.820, 2.0,   TRUE),

-- Generation 3 — from P20
(20,  25, '2024-01-17', 'Direct_Contact', 'Office, Islamabad',            3, 0.880, 8.0,   TRUE),
(20,  26, '2024-01-18', 'Airborne',       'Metro Station, Islamabad',     3, 0.720, 0.5,   TRUE),
(20,  27, '2024-01-18', 'Direct_Contact', 'Family Dinner, Islamabad',     3, 0.940, 4.0,   TRUE),

-- Generation 3 — from P21
(21,  28, '2024-01-18', 'Direct_Contact', 'Workplace, Lahore',            1, 0.850, 8.0,   TRUE),
(21,  29, '2024-01-19', 'Airborne',       'Bus, Quetta route',            5, 0.700, 6.0,   TRUE),

-- Generation 4 — from P24 (deepest branch — 4 hops from Patient Zero)
(24,  30, '2024-01-20', 'Direct_Contact', 'University Hostel, Lahore',    1, 0.900, 12.0,  TRUE),
(24,  31, '2024-01-20', 'Direct_Contact', 'University Hostel, Lahore',    1, 0.890, 12.0,  TRUE),
(24,  32, '2024-01-21', 'Airborne',       'Library, Karachi',             2, 0.750, 2.0,   TRUE),
(24,  33, '2024-01-21', 'Direct_Contact', 'Lab, Karachi',                 2, 0.820, 6.0,   TRUE),
(24,  34, '2024-01-22', 'Fomite',         'Market, Peshawar',             4, 0.600, 0.5,   TRUE),
(24,  35, '2024-01-22', 'Direct_Contact', 'Office, Quetta',               5, 0.810, 8.0,   TRUE);

-- -----------------------------------------------------------------------------
-- 9. DAILY_STATISTICS  (2.5 weeks of data, covering the outbreak progression)
-- -----------------------------------------------------------------------------
INSERT INTO Daily_Statistics
    (city_id, stat_date, new_cases, new_deaths, new_recoveries, active_cases,
     total_cases, total_deaths, total_recoveries, tests_conducted, positivity_rate, hospitalized, icu_occupied) VALUES

-- LAHORE (city_id=1)
(1,'2024-01-05',1,0,0,1,  1,  0,0,   150,0.67, 1,0),
(1,'2024-01-06',0,0,0,1,  1,  0,0,   175,0.00, 1,0),
(1,'2024-01-07',0,0,0,1,  1,  0,0,   200,0.00, 1,0),
(1,'2024-01-08',1,0,0,2,  2,  0,0,   220,0.45, 2,0),
(1,'2024-01-09',0,0,0,2,  2,  0,0,   210,0.00, 2,0),
(1,'2024-01-10',1,0,0,3,  3,  0,0,   230,0.43, 3,0),
(1,'2024-01-11',0,0,0,3,  3,  0,0,   245,0.00, 3,0),
(1,'2024-01-12',1,0,0,4,  4,  0,0,   260,0.38, 4,0),
(1,'2024-01-13',1,0,0,5,  5,  0,0,   280,0.36, 5,1),
(1,'2024-01-14',2,0,0,7,  7,  0,0,   310,0.65, 6,1),
(1,'2024-01-15',1,0,0,8,  8,  0,0,   340,0.29, 6,1),
(1,'2024-01-16',2,0,0,10, 10, 0,0,   380,0.53, 7,1),
(1,'2024-01-17',2,0,0,12, 12, 0,0,   420,0.48, 8,1),
(1,'2024-01-18',1,0,1,12, 13, 0,1,   450,0.22, 7,1),
(1,'2024-01-19',1,0,1,12, 14, 0,2,   470,0.21, 7,1),
(1,'2024-01-20',2,0,1,13, 16, 0,3,   500,0.40, 7,1),
(1,'2024-01-21',1,0,2,12, 17, 0,5,   520,0.19, 6,1),
(1,'2024-01-22',0,0,2,10, 17, 0,7,   480,0.00, 5,1),

-- KARACHI (city_id=2)
(2,'2024-01-09',1,0,0,1,  1,  0,0,   300,0.33, 1,0),
(2,'2024-01-10',0,0,0,1,  1,  0,0,   310,0.00, 1,0),
(2,'2024-01-11',1,0,0,2,  2,  0,0,   320,0.31, 2,1),
(2,'2024-01-12',1,0,0,3,  3,  0,0,   335,0.30, 3,1),
(2,'2024-01-13',0,0,0,3,  3,  0,0,   350,0.00, 3,1),
(2,'2024-01-14',0,0,0,3,  3,  0,0,   360,0.00, 3,1),
(2,'2024-01-15',1,0,0,4,  4,  0,0,   375,0.27, 4,1),
(2,'2024-01-16',2,0,0,6,  6,  0,0,   400,0.50, 5,1),
(2,'2024-01-17',1,0,0,7,  7,  0,0,   430,0.23, 6,1),
(2,'2024-01-18',0,0,0,7,  7,  0,0,   450,0.00, 6,1),
(2,'2024-01-19',0,0,1,6,  7,  0,1,   460,0.00, 5,1),
(2,'2024-01-20',1,1,1,5,  8,  1,2,   480,0.21, 4,0),  -- P8 death recorded
(2,'2024-01-21',2,0,1,6, 10,  1,3,   510,0.39, 4,0),
(2,'2024-01-22',0,1,2,3, 10,  2,5,   490,0.00, 3,0),  -- P15 death recorded

-- ISLAMABAD (city_id=3)
(3,'2024-01-13',1,0,0,1,  1,  0,0,   200,0.50, 1,0),
(3,'2024-01-14',2,0,0,3,  3,  0,0,   220,0.91, 2,0),
(3,'2024-01-15',1,0,0,4,  4,  0,0,   240,0.42, 3,0),
(3,'2024-01-16',1,0,0,5,  5,  0,0,   260,0.38, 3,0),
(3,'2024-01-17',3,0,0,8,  8,  0,0,   300,1.00, 5,0),
(3,'2024-01-18',3,0,0,11, 11, 0,0,   340,0.88, 6,0),
(3,'2024-01-19',0,0,1,10, 11, 0,1,   350,0.00, 5,0),
(3,'2024-01-20',0,0,1,9,  11, 0,2,   360,0.00, 4,0),
(3,'2024-01-21',0,0,2,7,  11, 0,4,   370,0.00, 3,0),
(3,'2024-01-22',0,0,2,5,  11, 0,6,   380,0.00, 2,0),

-- PESHAWAR (city_id=4)
(4,'2024-01-14',0,0,0,0,  0,  0,0,   180,0.00, 0,0),
(4,'2024-01-15',1,0,0,1,  1,  0,0,   190,0.53, 1,0),
(4,'2024-01-16',1,0,0,2,  2,  0,0,   200,0.50, 1,0),
(4,'2024-01-17',0,0,0,2,  2,  0,0,   210,0.00, 1,0),
(4,'2024-01-18',0,0,0,2,  2,  0,0,   220,0.00, 1,0),
(4,'2024-01-19',1,0,0,3,  3,  0,0,   230,0.43, 2,0),
(4,'2024-01-20',0,0,1,2,  3,  0,1,   240,0.00, 1,0),
(4,'2024-01-21',1,0,1,2,  4,  0,2,   250,0.40, 1,0),
(4,'2024-01-22',1,0,0,3,  5,  0,2,   260,0.38, 2,0),

-- QUETTA (city_id=5)
(5,'2024-01-19',1,0,0,1,  1,  0,0,   120,0.83, 0,0),
(5,'2024-01-20',0,0,0,1,  1,  0,0,   130,0.00, 0,0),
(5,'2024-01-21',0,0,0,1,  1,  0,0,   140,0.00, 0,0),
(5,'2024-01-22',1,0,0,2,  2,  0,0,   150,0.67, 1,0);

COMMIT;

-- =============================================================================
-- END OF SCRIPT 2
-- =============================================================================
