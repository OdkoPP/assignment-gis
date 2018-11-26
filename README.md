# PDT Project
**Application description**: Application helps visitors of Slovak part of The High Tatras to navigate in the High Tatra Mountains and to find the best route to get as close as possible to required position on map. There are three types of starting points - pakring areas, bus stops and train stops, that will be used as places to start the route. It is possible to choose type of starting point to be used as route starting point. There are also route analysis those provide information about environment and distances in specific environment that that route leads through.
Default map display and each navigation route shows also route color to help visitors to navigate in terrain. The amount of used colors is optimized to avoid frequent color changes on route.
To help user to navigate in map, there are dominant peaks shown in the map vissible from specific zoom level.

**Data source**: Open street map (https://www.openstreetmap.org)

**Technologies used**: PostgreSQL, Postgis, Angular 6, NodeJS + ExpressJS

## Install PostgreSQL and PostGIS

1.  Install PostgreSQL
    https://www.digitalocean.com/community/tutorials/how-to-install-and-use-postgresql-on-ubuntu-18-04

2.  Install PostGIS  (use proper version of PostgreSQL)
    https://www.gis-blog.com/how-to-install-postgis-2-3-on-ubuntu-16-04-lts/

    `sudo apt install postgis postgresql-10-postgis-2.4`

3. Install osm2pgsql
    https://wiki.openstreetmap.org/wiki/Osm2pgsql#For_Debian_or_Ubuntu

    `sudo apt-get install osm2pgsql`

## Create database and activate postgis

1.  Create database **gisdata** for spatial data and init PostGIS extension  (as user postgres)

    ```
    createdb -O postgres gisdata
    psql -c "CREATE EXTENSION postgis; CREATE EXTENSION postgis_topology;" gisdata
    ```

## Export data from OpenStreetMap

1.  Export required data from https://www.openstreetmap.org/ (or use file `data_tatry.osm`, initial SQL data transformation is tailor-made to this file)

2.  Check exported data format

    ```
    file map
    map: OpenStreetMap XML data
    ```


3.  Change exported data file extension to `.osm` if required

## Import data to PostgreSQL

1.  Import data to PostGIS using osm2pgsql (as user postgres)

    `osm2pgsql -d gisdata -s tatry.osm`

## Apply transformation on data

1. Run script in file `sqls/initialization.sql` (use pgAdmin for example)
   This script creates tables and functions

## Run application

1. Install npm packages

   `npm install`

2. Run Node.js and Angular 6 concurrently 

   `npm run serve`

3. Open http://localhost:4200/

## Notes
- To configure database connection go to 
    `./node-server/config/db-config.js`
- API prefix - `api/v1/`. Sample request `http://localhost:4200/api/v1/trails` (No parameters required for this example)
- All API endpoints are defined in `./node-server/routes/api-v1.js`
