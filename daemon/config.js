// Constantes partagées par le scan et le modèle (une seule définition).
export const DAY = 24 * 3600 * 1000;
export const WORK_MS = 20 * 1000;            // dernière ligne il y a moins de 20 s : la session travaille
export const SLEEP_MS = 30 * 60 * 1000;      // plus de 30 min : elle dort
export const RUIN_MS = 30 * DAY;             // plus de 30 jours : ruine
export const SESSION_MAX_AGE = 120 * DAY;    // au-delà, la session n'est même plus une ruine
export const SUB_MAX_AGE = 2 * 3600 * 1000;  // sous-agents : seulement les récents
export const BUCKET = 10 * 60 * 1000;        // granularité de la nourriture : 10 min
export const PORT = Number(process.env.AIMPIRE_PORT || 7777);
export const VERSION = '0.8.1';
export const SCHEMA = 1;
