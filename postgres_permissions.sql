CREATE DATABASE testing_permissions;

CREATE ROLE readonly NOINHERIT; -- NOINHERIT means we can't accidentally give readonly anything from another role (`readonly` will not inherit permissions from any roles granted to it)
CREATE ROLE edit IN GROUP readonly; -- This user will be able to modify the contents of tables, but not DDL or users.
CREATE ROLE temp_table_creator NOINHERIT; -- Grants ability to create temp tables
CREATE ROLE object_creator IN GROUP edit, temp_table_creator; -- This user will be able to modify table contents and DDL, but not create/edit users.
CREATE ROLE administrator CREATEDB CREATEROLE IN GROUP object_creator, pg_signal_backend, pg_monitor; -- Basically a superuser in specific schemas


CREATE USER liz LOGIN IN GROUP readonly PASSWORD '1234';  -- Liz's base user, with readonly permissions
CREATE USER liz_edit LOGIN IN GROUP edit PASSWORD '4321'; -- Liz needs to log in as this user to edit the contents of tables
CREATE USER ned LOGIN IN GROUP readonly PASSWORD 'abcd';  -- Ned's base user, with readonly permissions
CREATE USER ned_object_creator LOGIN IN GROUP object_creator NOINHERIT PASSWORD 'dcba'; -- Ned needs to log in as this user to create objects... but NOINHERIT means he'll then need to `SET ROLE object_creator` which ensures all objects are created by the same user.
CREATE USER jen_administrator CREATEDB CREATEROLE LOGIN IN GROUP administrator PASSWORD '!@#$'; -- Note that CreateDB and CreateRole can not be inherited

CREATE SCHEMA production AUTHORIZATION object_creator; -- It's incredibly important that object_creator owns all tables/views/sequences/etc.!
CREATE SCHEMA liz_dev_schema AUTHORIZATION liz;
CREATE SCHEMA ned_dev_schema AUTHORIZATION ned;

/***************************************/
/* Set up permissions for `production` */

-- prevent readonly users from writing to the public schema
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
-- revoke the ability of the `public` user to log in to the database
REVOKE ALL ON DATABASE analytics FROM PUBLIC;

-- `readonly`
-- inheritance passes this on to all the other roles
GRANT CONNECT ON DATABASE production TO readonly; -- the rest of the users inherit from this.
GRANT USAGE ON SCHEMA production TO readonly;
ALTER DEFAULT PRIVILEGES FOR ROLE object_creator IN SCHEMA production GRANT SELECT ON TABLES TO readonly;
-- if you had tables that already existed, you'd need to grant permissions with:
-- GRANT SELECT ON TABLES IN SCHEMA production TO readonly;

-- `edit`
ALTER DEFAULT PRIVILEGES FOR ROLE object_creator IN SCHEMA production GRANT USAGE ON SEQUENCES TO edit; -- needed if tables have sequential keys
ALTER DEFAULT PRIVILEGES FOR ROLE object_creator IN SCHEMA production GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES ON TABLES TO edit;

-- `temp_table_creator`
GRANT TEMPORARY ON DATABASE analytics to temp_table_creator;

-- `object_creator`
GRANT CREATE ON DATABASE analytics to object_creator;
GRANT ALL PRIVILEGES ON SCHEMA production TO object_creator; -- lets it modify and create all types of objects
ALTER DEFAULT PRIVILEGES GRANT ALL PRIVILEGES ON TABLES TO object_creator;
ALTER DEFAULT PRIVILEGES GRANT ALL PRIVILEGES ON SEQUENCES TO object_creator;
ALTER DEFAULT PRIVILEGES GRANT ALL PRIVILEGES ON FUNCTIONS TO object_creator;
ALTER DEFAULT PRIVILEGES GRANT ALL PRIVILEGES ON TYPES TO object_creator;
ALTER DEFAULT PRIVILEGES GRANT ALL PRIVILEGES ON SCHEMAS TO object_creator;

/************************************/
/* Create some things in production */
-- It's INCREDIBLY important that object_creator is the one who creates ALL objects!
SET ROLE object_creator;
DROP TABLE IF EXISTS production.object_creators_table CASCADE;
CREATE TABLE production.object_creators_table (id INTEGER GENERATED ALWAYS AS IDENTITY, firstcol TEXT);
INSERT INTO production.object_creators_table(firstcol) VALUES ('hi');

-- Let's see what happens if someone besides object_creator tries to makes a table; hopefully it fails!
SET ROLE ned_object_creator;
CREATE TABLE production.maxs_table (id SERIAL, firstcol text);
/*
 [42501] ERROR: permission denied for schema production Position: 14
*/

/**********************************************/
/* Check to see if things are set up properly */
SET ROLE liz;
-- Can `readonly` read tables in prod?
SELECT * FROM production.object_creators_table;
-- Can `readonly` edit table contents in prod?
INSERT INTO production.object_creators_table(firstcol) VALUES ('this should break');
/*
 [42501] ERROR: permission denied for relation object_creators_table
*/
-- Can `readonly` edit ddl in prod?
CREATE TABLE production.this_should_fail (nonsense text);
/*
 [42501] ERROR: permission denied for schema production Position: 14
*/
ALTER TABLE production.object_creators_table ADD COLUMN badcolumn text;
/*
 [42501] ERROR: must be owner of relation object_creators_table
*/

SET ROLE liz_edit;
-- Can `edit` read tables in prod?
SELECT * FROM production.object_creators_table;
-- Can `edit` edit table contents in prod?
INSERT INTO production.object_creators_table(firstcol) VALUES ('this should succeed');
-- Can `edit` edit ddl in prod?
CREATE TABLE production.this_should_fail (nonsense text);
/*
 [42501] ERROR: permission denied for schema production Position: 14
*/
ALTER TABLE production.object_creators_table ADD COLUMN badcol text;
/*
 [42501] ERROR: must be owner of relation object_creators_table
*/

SET ROLE ned_object_creator;
-- Can `object_creator` read tables in prod?
SELECT * FROM production.object_creators_table;
/*
[42501] ERROR: permission denied for schema production Position: 15
*/
--Right!  It has noinherit to ensure everything is owned by the same user.  Let's switch over.

SET ROLE object_creator;
-- Can `object_creator` read tables in prod?
SELECT * FROM production.object_creators_table;
-- Can `edit` edit table contents in prod?
INSERT INTO production.object_creators_table(firstcol) VALUES ('this should succeed');
-- Can `edit` edit ddl in prod?
CREATE TABLE production.this_should_succeed (nonsense text);
/*
 [42501] ERROR: permission denied for schema production Position: 14
*/
ALTER TABLE production.object_creators_table ADD COLUMN secondcol text;

-- What happens in the dev schemas?
