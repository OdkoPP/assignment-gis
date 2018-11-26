const express = require('express');
const router = express.Router();
const { Pool, Client } = require('pg');

const dbConfig = require('../config/db-config').dbConfig;
var pool;

(function establishPGConnection() {
  try {
    pool = new Pool(dbConfig);
    pool.query('SELECT NOW()', err => {
      if ( err === undefined ) console.log('Connection to database established successfully');
    });
    pool.on('error', err => console.error('Unexpected error on idle client', err));
  } catch (e) {
    console.log('Error during database connection establishment', e );
  }
})();

/* GET home page. */
router.get('/', function(req, res, next) {
  res.setHeader('Content-Type', 'application/json');
  res.send(JSON.stringify({ message: 'API V1 works' }));
});

router.get('/test-db-con', (req, res, next) => {
  res.setHeader('Content-Type', 'application/json');

  pool.connect()
    .then(client => {
        client.query('SELECT NOW()')
          .then(() => {
            client.release();
            res.send(JSON.stringify({ message: 'Connection established' }))
          })
          .catch(err => {
            client.release();
            res.send(JSON.stringify({ message: 'Error', error: err })) 
          });
    });
});

router.get('/trails', (req, res, next) => {
  res.setHeader('Content-Type', 'application/json');

  pool.connect()
    .then(client => {
      let clientReleased = false;

      client.query(`
        SELECT *, ST_AsGeoJSON(t.geom)::json AS geometry
        FROM trails t
      `)
        .then(data => {
          client.release();
          clientReleased = true;

          res.send(JSON.stringify( toGeoJson(data.rows)) );
        })
        .catch(err => {
          if (clientReleased === false) {
            client.release();
          }

          res.send(JSON.stringify({ message: 'Error', error: err }));
        })
    });
});

router.get('/route_analysis/:lon/:lat', (req, res, next) => {
  res.setHeader('Content-Type', 'application/json');

  const activeStartingPoints = req.query.activeStartingPoints || [];

  if (activeStartingPoints.length === 0) {
    res.send(JSON.stringify({
      type: 'FeatureCollection',
      features: []
    }));
    return;
  }

  pool.connect()
    .then(client => {
      let clientReleased = false;

      client.query(`
        WITH final_route AS (
          SELECT ST_Union(geom) AS geom
          FROM find_route_to_point(${req.params.lon}, ${req.params.lat}, ARRAY['${activeStartingPoints.join("','")}'])
        ),
        all_intersections AS (
          SELECT
            p.osm_id AS id,
            coalesce(p.natural, p.landuse) AS type,
            ST_Transform(t.geom, 4326) AS polygon_geom,
            ST_Intersection(ST_Transform(p.way, 4326), t.geom) AS route_geom,
            ST_Length(ST_Intersection(ST_Transform(p.way, 4326), t.geom), true) AS distance
          FROM planet_osm_polygon p
          LEFT JOIN final_route t ON ST_Intersects(t.geom, ST_Transform(p.way,4326))
          WHERE
              ST_Intersects(ST_Transform(p.way, 4326), t.geom)
            AND p.boundary IS NULL
            AND (
              p.natural IS NOT NULL
              OR p.landuse IS NOT NULL
            )
          ORDER BY p.osm_id
        ),
        simplified_intersections AS (
          SELECT
            ST_Union(route_geom) AS geom,
            sum(distance) AS distance,
            type
          FROM all_intersections
          GROUP BY type
        ),
        not_intersected AS (
          SELECT 
            ST_Difference(f.geom, s.geom) AS geom,
            ST_Length(ST_Difference(f.geom, s.geom), true) AS distance,
            null AS type
          FROM 
            final_route f, 
            (
              SELECT ST_Buffer(ST_Union(geom), 0.000001) AS geom
              FROM simplified_intersections
            ) AS s
        ),
        joined AS (
          SELECT
            coalesce(s.geom, n.geom) AS geom,
            coalesce(s.distance, n.distance) AS distance,
            coalesce(s.type, n.type) AS type
          FROM simplified_intersections s
          FULL OUTER JOIN not_intersected n ON s.type = n.type
        )
        SELECT
          *,
          ST_AsGeoJSON(geom)::json AS geometry
        FROM joined 
      `)
        .then(data => {
          data.rows.forEach( e => e.id = 0)       // quick fix
          client.release();
          clientReleased = true;

          res.send(JSON.stringify( toGeoJson(data.rows)) );
        })
        .catch(err => {
          console.log(err);
          if (clientReleased === false) {
            client.release();
          }

          res.send(JSON.stringify({ message: 'Error', error: err }));
        })
    });
});

router.get('/dominant_peaks', (req, res, next) => {
  res.setHeader('Content-Type', 'application/json');

  pool.connect()
    .then(client => {
      let clientReleased = false;

      client.query(`
        SELECT *, ST_AsGeoJSON(p.geom)::json AS geometry
        FROM dominant_peaks p
      `)
        .then(data => {
          client.release();
          clientReleased = true;

          res.send(JSON.stringify( toGeoJson(data.rows)) );
        })
        .catch(err => {
          if (clientReleased === false) {
            client.release();
          }

          res.send(JSON.stringify({ message: 'Error', error: err }));
        })
    });
});

router.get('/starting_points', (req, res, next) => {
  res.setHeader('Content-Type', 'application/json');

  const activeStartingPoints = req.query.activeStartingPoints || [];
 
  if (activeStartingPoints.length === 0) {
    res.send(JSON.stringify({
      type: 'FeatureCollection',
      features: []
    }));
    return;
  }

  pool.connect()
    .then(client => {
      let clientReleased = false;

      client.query(`
        SELECT *, ST_AsGeoJSON(p.geom)::json AS geometry
        FROM starting_points p
        WHERE p.type = ANY(ARRAY['${activeStartingPoints.join("','")}'])
      `)
        .then(data => {
          client.release();
          clientReleased = true;

          res.send(JSON.stringify( toGeoJson(data.rows)) );
        })
        .catch(err => {
          if (clientReleased === false) {
            client.release();
          }

          res.send(JSON.stringify({ message: 'Error', error: err }));
        })
    });
});

router.get('/route_to_nearest_starting_point/:lon/:lat', (req, res, next) => {
  res.setHeader('Content-Type', 'application/json');

  const activeStartingPoints = req.query.activeStartingPoints || [];

  if (activeStartingPoints.length === 0) {
    res.send(JSON.stringify({
      type: 'FeatureCollection',
      features: []
    }));
    return;
  }

  pool.connect()
    .then(client => {
      let clientReleased = false;

      client.query(`
        SELECT
          *,
          ST_AsGeoJSON(r.geom)::json AS geometry
        FROM find_route_to_point(${req.params.lon}, ${req.params.lat}, ARRAY['${activeStartingPoints.join("','")}']) r
      `)
        .then(data => {
          data.rows.forEach( e => e.id = 0)       // quick fix
          client.release();
          clientReleased = true;

          res.send(JSON.stringify( toGeoJson(data.rows)) );
        })
        .catch(err => {
          if (clientReleased === false) {
            client.release();
          }

          res.send(JSON.stringify({ message: 'Error', error: err }));
        })
    });
});

function toGeoJson(rows){
  return  {
    type: "FeatureCollection",
    features: rows.reduce( (res, cur) => {
      res.push({
        type: 'Feature',
        id: parseInt(cur.id),
        geometry: cur.geometry,
        properties: cur
      });
      delete cur.geometry;
      return res;
    }, [])
  };
}

module.exports = router;
