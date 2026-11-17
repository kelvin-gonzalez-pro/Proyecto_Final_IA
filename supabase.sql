-- =====================================================================
-- Proyecto Final - Asistente de Cotizaciones para Corredores
-- Scripts de Supabase (ejecutar en SQL Editor, en este orden)
-- =====================================================================

-- ---------------------------------------------------------------------
-- 01. Vector Store: extensión pgvector, tabla y función de búsqueda
--     Embeddings: Cohere embed-multilingual-v3.0 (1024 dimensiones)
-- ---------------------------------------------------------------------
create extension if not exists vector;

create table documents (
  id bigserial primary key,
  content text,
  metadata jsonb,
  embedding vector(1024)
);

create function match_documents (
  query_embedding vector(1024),
  match_count int default null,
  filter jsonb default '{}'
) returns table (
  id bigint,
  content text,
  metadata jsonb,
  similarity float
)
language plpgsql
as $$
#variable_conflict use_column
begin
  return query
  select
    id,
    content,
    metadata,
    1 - (documents.embedding <=> query_embedding) as similarity
  from documents
  where metadata @> filter
  order by documents.embedding <=> query_embedding
  limit match_count;
end;
$$;

-- Seguridad: RLS activado (sin políticas públicas). Solo accede service_role.
alter table documents enable row level security;

-- ---------------------------------------------------------------------
-- 02. Permisos para la clave de servicio que usa n8n
-- ---------------------------------------------------------------------
grant usage on schema public to service_role;
grant all on table public.documents to service_role;
grant usage, select on sequence public.documents_id_seq to service_role;
grant execute on function public.match_documents(vector, int, jsonb) to service_role;

-- ---------------------------------------------------------------------
-- 03. Numeración correlativa de cotizaciones (atómica)
--     Una secuencia evita que dos solicitudes simultáneas (correo y
--     Telegram) reciban el mismo número.
--     n8n la llama con: POST /rest/v1/rpc/siguiente_cotizacion  body {}
--     Respuesta: {"numero": "COT-20261116-0001"}
-- ---------------------------------------------------------------------
create sequence cotizacion_seq;

create function siguiente_cotizacion()
returns json
language sql
as $$
  select json_build_object(
    'numero',
    'COT-' || to_char(now() at time zone 'America/Santiago', 'YYYYMMDD')
    || '-' || lpad(nextval('cotizacion_seq')::text, 4, '0')
  );
$$;

grant usage on sequence cotizacion_seq to service_role;
grant execute on function siguiente_cotizacion() to service_role;

-- ---------------------------------------------------------------------
-- Mantenimiento
-- ---------------------------------------------------------------------
-- Recargar el FAQ (antes de volver a ejecutar la ingesta):
--   truncate table documents;
-- Reiniciar la numeración de cotizaciones:
--   alter sequence cotizacion_seq restart with 1;
