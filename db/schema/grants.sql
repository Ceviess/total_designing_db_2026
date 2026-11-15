/*
Роль inspector и права
*/

set search_path to kuzmin_food, exts;

create schema if not exists exts;
create extension if not exists "uuid-ossp" with schema exts;


do $$
begin
    if not exists (select 1 from pg_roles where rolname = 'inspector') then
        create role inspector login password 'NetoSQL2025';
    end if;
end $$;

grant all privileges on schema kuzmin_food to inspector;

grant usage on schema exts to inspector;

grant select, insert, update, delete
    on all tables in schema kuzmin_food to inspector;

grant execute on all functions in schema kuzmin_food to inspector;
grant execute on all procedures in schema kuzmin_food to inspector;

grant usage on schema information_schema to inspector;
grant usage on schema pg_catalog to inspector;
