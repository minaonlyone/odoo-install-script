-- pgvector is required by the Odoo Enterprise AI modules.
-- Creating it in template1 means every database Odoo creates inherits it, which matters
-- because the odoo role is deliberately not a superuser and cannot CREATE EXTENSION.
\connect template1
CREATE EXTENSION IF NOT EXISTS vector;
