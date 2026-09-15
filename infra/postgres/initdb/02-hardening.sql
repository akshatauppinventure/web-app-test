-- Per-role safety settings (ADR-0009 §4). Runs once at first initialisation.
ALTER ROLE app_rw SET statement_timeout = '15s';
ALTER ROLE app_rw SET idle_in_transaction_session_timeout = '30s';
ALTER ROLE app_rw SET lock_timeout = '5s';
ALTER ROLE app_rw SET search_path = public;
ALTER ROLE app_migrator SET statement_timeout = '10min';
ALTER ROLE app_migrator SET lock_timeout = '1min';
ALTER ROLE app_migrator SET search_path = public;
ALTER ROLE keycloak SET search_path = public;
-- The superuser is for bootstrap/emergencies only; make accidental use loud in the logs.
ALTER ROLE postgres SET log_statement = 'all';
