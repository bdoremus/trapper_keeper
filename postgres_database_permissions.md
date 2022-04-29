```postgresql
CREATE DATABASE testing_permissions;
```

```postgresql
CREATE ROLE readonly NOINHERIT; -- NOINHERIT means we can't accidentally give readonly anything from another role (`readonly` will not inherit permissions from any roles granted to it)
CREATE ROLE edit IN GROUP readonly; -- This user will be able to modify the contents of tables, but not DDL or users.
CREATE ROLE object_creator IN GROUP edit; -- This user will be able to modify table contents and DDL, but not users.
CREATE ROLE administrator CREATEDB CREATEROLE IN GROUP object_creator, pg_signal_backend, pg_monitor; -- Basically a superuser in specific schemas
```

```postgresql
CREATE USER liz LOGIN IN GROUP readonly PASSWORD '1234';  -- Liz's base user, with readonly permissions
CREATE USER liz_edit LOGIN IN GROUP edit PASSWORD '4321'; -- Liz needs to log in as this user to edit the contents of tables
CREATE USER ned LOGIN IN GROUP readonly PASSWORD 'abcd';  -- Ned's base user, with readonly permissions
CREATE USER ned_object_creator IN GROUP object_creator NOINHERIT PASSWORD 'dcba'; -- Ned needs to log in as this user to create objects... but NOINHERIT means he'll then need to `SET ROLE object_creator` which ensures all objects are created by the same user.
CREATE USER jen_administrator CREATEDB CREATEROLE LOGIN IN GROUP administrator PASSWORD '!@#$'; -- Note that CreateDB and CreateRole can not be inherited
```

Note that you could also make `ned_object_creator` NOLOGIN and grant it to `ned`.  For auditing purposes, we prefer to force users to intentionally log in to an account separate from their standard one.

```postgresql
CREATE SCHEMA production AUTHORIZATION object_creator; -- It's incredibly important that object_creator owns all tables/views/sequences/etc.!
CREATE SCHEMA liz_dev_schema AUTHORIZATION liz;
CREATE SCHEMA ned_dev_schema AUTHORIZATION ned;
```

# Set up permissions for `production`

## `readonly`
Inheritance passes this on to all the other roles
```postgresql
GRANT USAGE ON SCHEMA production TO readonly;
ALTER DEFAULT PRIVILEGES FOR ROLE object_creator IN SCHEMA production GRANT SELECT ON TABLES TO readonly;
```
If you had tables that already existed, you'd need to grant permissions with:
```postgresql
GRANT SELECT ON TABLES IN SCHEMA production TO readonly;
```


## `edit`
```postgresql
ALTER DEFAULT PRIVILEGES FOR ROLE object_creator IN SCHEMA production GRANT USAGE ON SEQUENCES TO edit; -- needed if tables have sequential keys
ALTER DEFAULT PRIVILEGES FOR ROLE object_creator IN SCHEMA production GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES ON TABLES TO edit;
```


## `object_creator`
```postgresql
GRANT ALL PRIVILEGES ON SCHEMA production TO object_creator; -- lets it modify and create all types of objects
```


# Create some things in production
It's INCREDIBLY important that object_creator is the one who creates ALL objects!
```postgresql
SET ROLE object_creator;
DROP TABLE IF EXISTS production.object_creators_table;
CREATE TABLE IF NOT EXISTS production.object_creators_table (id int GENERATED ALWAYS AS IDENTITY, firstcol text);
INSERT INTO production.object_creators_table(firstcol) VALUES ('hi');
```

Let's see what happens if someone besides object_creator tries to make a table; hopefully it fails!
```postgresql
SET ROLE ned_object_creator;
CREATE TABLE production.maxs_table (id SERIAL, firstcol text);
```
> [42501] ERROR: permission denied for schema production Position: 14

# Check to see if things are set up properly
## `readonly`
```postgresql
SET ROLE liz;
```
Can `readonly` read tables in prod?
```postgresql
SELECT * FROM production.object_creators_table;
```
Can `readonly` edit table contents in prod?
```postgresql
INSERT INTO production.object_creators_table(firstcol) VALUES ('this should break');
```
> [42501] ERROR: permission denied for relation object_creators_table

Can `readonly` edit ddl in prod?
```postgresql
CREATE TABLE production.this_should_fail (nonsense text);
```
> [42501] ERROR: permission denied for schema production Position: 14

```postgresql
ALTER TABLE production.object_creators_table ADD COLUMN badcolumn text;
````
> [42501] ERROR: must be owner of relation object_creators_table

# `edit`
```postgresql
SET ROLE liz_edit;
```
Can `edit` read tables in prod?
```postgresql
SELECT * FROM production.object_creators_table;
```
Can `edit` edit table contents in prod?
```postgresql
INSERT INTO production.object_creators_table(firstcol) VALUES ('this should succeed');
```
Can `edit` edit ddl in prod?
```postgresql
CREATE TABLE production.this_should_fail (nonsense text);
```
> [42501] ERROR: permission denied for schema production Position: 14
```postgresql
ALTER TABLE production.object_creators_table ADD COLUMN newcolumn text;
```
> [42501] ERROR: must be owner of relation object_creators_table

## `object_creator`
```postgresql
SET ROLE ned_object_creator;
```
Can `ned_object_creator` read tables in prod?
```postgresql
SELECT * FROM production.object_creators_table;
```
> [42501] ERROR: permission denied for schema production Position: 15
Right!  It has noinherit to ensure everything is owned by the same user.  Let's switch over.

```postgresql
SET ROLE object_creator;
```
Can `object_creator` read tables in prod?
```postgresql
SELECT * FROM production.object_creators_table;
```
Can `object_creator` edit table contents in prod?
```postgresql
INSERT INTO production.object_creators_table(firstcol) VALUES ('this should succeed');
```
Can `object_creator` edit ddl in prod?
```postgresql
CREATE TABLE production.this_should_succeed (sense text);
```
```postgresql
ALTER TABLE production.object_creators_table ADD COLUMN newcolumn text;
```