-- Spojenie end pointov a routes a bodov na routes pre pg_rputing
SELECT 
	coalesce(ST_Buffer(p.geom, 0.0025), r.geom, v.the_geom) AS geom,
	v.id AS vertice_id,
	r.source AS route_source,
	r.target AS route_target
FROM routes r
FULL OUTER JOIN starting_points p ON p.osm_id = r.osm_id
FULL OUTER JOIN routes_vertices_pgr v ON v.id = r.osm_id







WITH areas_around_starting_points AS (
	SELECT ST_Union(ST_Buffer(p.geom, 0.0005)) AS geom 
	FROM trails t
	FULL OUTER JOIN starting_points p ON p.osm_id = t.id
),
routes_around_starting_points AS (
	SELECT r.*
	FROM routes r
	INNER JOIN areas_around_starting_points aasp ON ST_Intersects(r.geom, aasp.geom)
)

SELECT
	DISTINCT ON (p.osm_id) p.osm_id,
	r.osm_id AS nearest_route_osm_id,
	r.source AS nearest_route_source,
	r.target AS nearest_route_target,
	ST_Distance(r.geom, p.geom, true) AS nearest_route_distence,
	ST_ClosestPoint(r.geom, p.geom) AS nearest_route_nearest_point,
	p.*
FROM starting_points p
LEFT JOIN routes r ON ST_DWithin(p.geom, r.geom, 0.001)
WHERE r.geom IS NOT NULL
ORDER BY 
	p.osm_id,
	ST_Distance(p.geom, r.geom, true)
