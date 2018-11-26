DROP TABLE IF EXISTS dominant_peaks;

CREATE TABLE dominant_peaks AS (
	WITH park_boundary AS (	-- TANAP in Slovakia boundary
		SELECT ST_Transform(p.way, 4326) AS geom
		FROM planet_osm_polygon p
		WHERE p.name = 'Tatranský národný park'
	),
	peaks AS (
		SELECT
			ST_Transform(p.way, 4326) AS geom,
			ST_Buffer(ST_Transform(p.way, 4326), 0.005) AS zone_1,
			ST_Buffer(ST_Transform(p.way, 4326), 0.01) AS zone_2,
			ST_Buffer(ST_Transform(p.way, 4326), 0.015) AS zone_3,
			p.*
		FROM planet_osm_point p
		INNER JOIN park_boundary b ON ST_Intersects(ST_Transform(p.way, 4326), b.geom)
		WHERE
				p.natural = 'peak'
			AND	p.ele::float > 1600
	)
	SELECT
		p.osm_id,
		p.ele,
		p.name,
		p.geom
	FROM peaks p
	WHERE
		(
			SELECT count(*)
			FROM peaks p2
			WHERE
					p.osm_id != p2.osm_id
				AND	ST_Intersects(p2.geom, p.zone_1)
				AND p2.ele::float > p.ele::float
		) = 0
		AND (
			SELECT count(*)
			FROM peaks p2
			WHERE
					p.osm_id != p2.osm_id
				AND	ST_Intersects(p2.geom, p.zone_2)
				AND p2.ele::float > (p.ele::float * 1.05)
		) = 0
		AND (
			SELECT count(*)
			FROM peaks p2
			WHERE
					p.osm_id != p2.osm_id
				AND	ST_Intersects(p2.geom, p.zone_3)
				AND p2.ele::float > (p.ele::float * 1.1)
		) = 0
	ORDER BY p.name
)

DROP TABLE IF EXISTS trails;

CREATE TABLE trails AS (
	-- All lines osm_id that are part of any trail
	WITH trails_parts AS (
		SELECT
			r.id,
			-- r.tags is array of values. I need key->value mapping. If key is "name" and value is index of "name" plus one
			COALESCE(r.tags[array_position(r.tags, 'name') + 1], r.tags[array_position(r.tags, 'description') + 1]) AS name,
			r.tags[array_position(r.tags, 'colour') + 1] AS color,
			unnest(r.parts) AS line_osm_id_of_trail_part		-- rels.tags array to rows
		FROM public.planet_osm_rels r
		WHERE 
				'colour' = ANY(r.tags)
			AND	'hiking' = ANY(r.tags)
			AND NOT r.id = ANY('{1844611, 2120412, 1307381, 1706987}')		-- routes outside TANAP
	),
	-- TANAP in Slovakia boundary
	park_boundary AS (
		SELECT ST_Transform(p.way, 4326) AS geom
		FROM planet_osm_polygon p
		WHERE p.name = 'Tatranský národný park'
	),
	-- Assign lines to trails_parts
	trails_including_pl AS (
		SELECT 
			t.id,
			t.name,
			t.color,
			ST_Transform(ST_Union(l.way), 4326) AS geom
		FROM trails_parts t
		JOIN planet_osm_line l ON t.line_osm_id_of_trail_part = l.osm_id
		GROUP BY t.id, t.name, t.color
		ORDER BY t.name
	)
	-- Leave only trails in Slovakia (98)
	SELECT t.*
	FROM 
		park_boundary b, 
		trails_including_pl t
	WHERE ST_Intersects(b.geom, t.geom)
) WITH DATA;

DROP TABLE IF EXISTS starting_points;

CREATE TABLE starting_points AS (
	-- Parking areas
	WITH parking_polygon AS (
		SELECT
			p.osm_id,
			p.name,
			ST_Centroid(ST_Transform(p.way, 4326)) AS geom,
			'parking' AS type
		FROM planet_osm_polygon p
		WHERE
		(
				p.amenity = 'parking'
			AND (
				(
						p.access <> 'private'
					AND 	p.access <> 'permissive'
					AND 	p.access <> 'designated'
					AND 	p.access <> 'customers'
				) OR p.access IS NULL
			)
			AND NOT p.osm_id = ANY('{558596980,369377677,561931566,402047773}')	-- Not accessible parking areas
			AND NOT p.osm_id = ANY('{85511474,520872919,327687182}')	-- Poland
		)
	),
	parking_point AS (
		SELECT
			p.osm_id,
			p.name,
			ST_Transform(p.way, 4326) AS geom,
			'parking' AS type
		FROM planet_osm_point p
		WHERE
		(
				p.amenity = 'parking'
			AND (
				(
						p.access <> 'private'
					AND 	p.access <> 'permissive'
					AND 	p.access <> 'designated'
					AND 	p.access <> 'customers'
				) OR p.access IS NULL
			)
			AND NOT p.osm_id = ANY('{5851135034, 1195148475}')	-- Poland
		)
	),
	-- Train stations
	train AS (
		SELECT
			p.osm_id,
			p.name,
			ST_Transform(p.way, 4326) AS geom,
			'train' AS type
		FROM planet_osm_point p
		WHERE
		(
				p.railway = 'station'
			OR	p.railway = 'halt'
		) 
		AND 	NOT p.osm_id = ANY('{30933030, 30933044}')
		AND 	NOT p.osm_id = ANY('{3554992925, 1423303003, 1446015729}')		-- Poland
	),
	-- Bus stations
	bus AS (
		SELECT
			p.osm_id,
			p.name,
			ST_Transform(p.way, 4326) AS geom,
			'bus' AS type
		FROM planet_osm_point p
		WHERE
		(
				p.highway = 'bus_stop'
			OR	p.amenity = 'bus_station'
		) 
		AND 	NOT p.osm_id = ANY('{30933030, 30933044}')
		AND 	NOT p.osm_id = ANY('{3554992925, 1423303003, 1446015729}')		-- Poland
	),
	-- Combine all starting points together
	starting_points AS (
		SELECT
			coalesce(p1.osm_id, p2.osm_id, b.osm_id, t.osm_id) AS osm_id,
			coalesce(p1.name, p2.name, b.name, t.name, '') AS name,
			coalesce(p1.type, p2.type, b.type, t.type, '') AS type,
			coalesce(p1.geom, p2.geom, b.geom, t.geom) AS geom
		FROM parking_polygon p1
		FULL OUTER JOIN parking_point p2 ON p1.osm_id = p2.osm_id
		FULL OUTER JOIN bus b ON p1.osm_id = b.osm_id
		FULL OUTER JOIN train t ON p1.osm_id = t.osm_id
	)
	SELECT *
	FROM starting_points p
	WHERE EXISTS(		-- Max 1.5 km from trail
		SELECT *
		FROM trails t
		WHERE ST_DWithin(p.geom, t.geom, 1500, true)
	)
) WITH DATA;

DROP TABLE IF EXISTS routes;				-- Table that will be used for pg_routing

CREATE TABLE routes AS (
	WITH poland AS (				-- "poland" view will be used to remove parts of map, taht belongs to Poland
		SELECT 
			ST_Transform(p.way, 4326) AS geom, 
			*
		FROM planet_osm_polygon p
		WHERE
				p.boundary IS NOT NULL
			AND (				-- List of some huge polygons in Poland
					osm_id = -5194954
				OR osm_id = -5183252
				OR osm_id = -2226518
				OR osm_id = -5195372
				OR osm_id = -4581810
				OR osm_id = -2838555
				OR osm_id = -5184009
				OR osm_id = -5183057
				OR osm_id = -5177459
				OR osm_id = -2431742
			)
	)
	SELECT 
		l.osm_id,
		ST_Transform(l.way, 4326) AS geom,
		l.highway,
		l.name,
		l.surface,
		l.tracktype
	FROM public.planet_osm_line l			-- Select lines
	LEFT JOIN poland p ON ST_Contains(p.way, l.way)
	WHERE
			p.way IS NULL
		AND 	l.waterway IS NULL		-- No rivers
		AND 	l.boundary IS NULL		-- No boundaries (e.g. administrative)
		AND (					-- Only accessible paths
			(
					l.access <> 'private'
				AND 	l.access <> 'no'
			)
			OR	l.access IS NULL
		)
		AND 	l.power IS NULL			-- No wirings
		AND 	l.barrier IS NULL		-- No bariers (e.g. clifs, fances)
		AND 	l.natural IS NULL		-- No naturals
		AND 	l.aerialway IS NULL		-- No aerialways
		AND 	l.highway <> 'motoway'		-- Exclude motoways (e.g. D1)
		AND 	EXISTS (			-- OSM didnt let us to select exact polygon to download
							-- Because of that we will remove parts of the map that 
							-- will never be used to navigate user to reduce 
							-- complexity of routing
			SELECT *
			FROM planet_osm_point p 
			WHERE
				(
						p.name = 'Zakopane' 
					AND 	p.place = 'town' 
					AND NOT ST_DWithin(ST_Transform(l.way, 4326), ST_Transform(p.way, 4326), 6500, true)
				)
		)
		AND EXISTS (
			SELECT *
			FROM planet_osm_point p 
			WHERE
				(
						p.name = 'Dzianisz'
					AND 	p.place = 'village'
					AND NOT ST_DWithin(ST_Transform(l.way, 4326), ST_Transform(p.way, 4326), 3400, true)
				)
		)
		AND EXISTS (
			SELECT *
			FROM planet_osm_point p 
			WHERE
				(
						p.name = 'Bukowina Tatrzańska'
					AND 	p.place = 'village'
					AND NOT ST_DWithin(ST_Transform(l.way, 4326), ST_Transform(p.way, 4326), 3800, true)
				)
		)
 		AND EXISTS (
 			SELECT *
 			FROM planet_osm_point p 
 			WHERE
 				(
 						p.name = 'Poronin'
 					AND 	p.place = 'village'
 					AND NOT ST_DWithin(ST_Transform(l.way, 4326), ST_Transform(p.way, 4326), 10000, true)
 				)
		)
		AND EXISTS (
 			SELECT *
 			FROM planet_osm_point p 
 			WHERE
 				(
 						p.name = 'Kościelisko'
 					AND 	p.place = 'village'
 					AND NOT ST_DWithin(ST_Transform(l.way, 4326), ST_Transform(p.way, 4326), 5000, true)
 				)
		)
		AND EXISTS (
 			SELECT *
 			FROM planet_osm_point p 
 			WHERE
 				(
 						p.name = 'Witów'
 					AND 	p.place = 'village'
 					AND NOT ST_DWithin(ST_Transform(l.way, 4326), ST_Transform(p.way, 4326), 1450, true)
 				)
		)
		AND EXISTS (
 			SELECT *
 			FROM planet_osm_point p 
 			WHERE
 				(
 						p.name = 'Liptovský Mikuláš'
 					AND 	p.place = 'town'
 					AND NOT ST_DWithin(ST_Transform(l.way, 4326), ST_Transform(p.way, 4326), 4000, true)
 				)
		)
 		AND EXISTS (
  			SELECT *
  			FROM planet_osm_point p 
  			WHERE
  				(
  						p.name = 'Veľká Lomnica'
  					AND 	p.place = 'village'
  					AND NOT ST_DWithin(ST_Transform(l.way, 4326), ST_Transform(p.way, 4326), 7300, true)
  				)
 		)
		AND EXISTS (
 			SELECT *
 			FROM planet_osm_point p 
 			WHERE
 				(
 						p.name = 'Veľký Slavkov'
 					AND 	p.place = 'village'
 					AND NOT ST_DWithin(ST_Transform(l.way, 4326), ST_Transform(p.way, 4326), 5500, true)
 				)
		)
		AND EXISTS (
 			SELECT *
 			FROM planet_osm_point p 
 			WHERE
 				(
 						p.name = 'Batizovce'
 					AND 	p.place = 'village'
 					AND NOT ST_DWithin(ST_Transform(l.way, 4326), ST_Transform(p.way, 4326), 3500, true)
 				)
		)
		AND EXISTS (
 			SELECT *
 			FROM planet_osm_point p 
 			WHERE
 				(
 						osm_id = '29528026'		-- Vazec
 					AND NOT ST_DWithin(ST_Transform(l.way, 4326), ST_Transform(p.way, 4326), 5500, true)
 				)
		)
		AND EXISTS (
 			SELECT *
 			FROM planet_osm_point p 
 			WHERE
 				(
 						p.name = 'Dlhá hora'
 					AND 	p.natural = 'peak'
 					AND NOT ST_DWithin(ST_Transform(l.way, 4326), ST_Transform(p.way, 4326), 6800, true)
 				)
		)
		AND EXISTS (
 			SELECT *
 			FROM planet_osm_point p 
 			WHERE
 				(
 						p.name = 'Rakúsy'
 					AND p.place = 'village'
 					AND NOT ST_DWithin(ST_Transform(l.way, 4326), ST_Transform(p.way, 4326), 4500, true)
 				)
		)
		AND EXISTS (
 			SELECT *
 			FROM planet_osm_point p 
 			WHERE
 				(
 						p.name = 'Veľká Franková'
 					AND 	p.place = 'village'
 					AND NOT ST_DWithin(ST_Transform(l.way, 4326), ST_Transform(p.way, 4326), 7000, true)
 				)
		)
		AND EXISTS (
 			SELECT *
 			FROM planet_osm_point p 
 			WHERE
 				(
 						p.name = 'Brezovica'
 					AND 	p.place = 'village'
 					AND NOT ST_DWithin(ST_Transform(l.way, 4326), ST_Transform(p.way, 4326), 7500, true)
 				)
		)
		AND EXISTS (
 			SELECT *
 			FROM planet_osm_point p 
 			WHERE
 				(
 						p.name = 'Savoš'
 					AND 	p.natural = 'peak'
 					AND NOT ST_DWithin(ST_Transform(l.way, 4326), ST_Transform(p.way, 4326), 2500, true)
 				)
		)
		AND EXISTS (
 			SELECT *
 			FROM planet_osm_point p 
 			WHERE
 				(
 						p.name = 'Bobrovečky'
 					AND 	p.place = 'locality'
 					AND NOT ST_DWithin(ST_Transform(l.way, 4326), ST_Transform(p.way, 4326), 5000, true)
 				)
		)
);

WITH intersections AS (		-- All intersections including touches and dupicaties
	SELECT
		a.osm_id AS intersected_osm_id,
		ST_Intersection(a.geom, b.geom) AS inters
	FROM
		routes AS a
	INNER JOIN routes b ON ST_Intersects(a.geom, b.geom)
	WHERE
			a.osm_id != b.osm_id
		AND NOT ST_IsEmpty(ST_Intersection(a.geom, b.geom))
),
starting_point_intersections AS (
	SELECT
		DISTINCT ON (p.osm_id) null,
		r.osm_id AS intersected_osm_id,
		ST_Intersection( 
			ST_Snap( r.geom, ST_ClosestPoint(r.geom, p.geom), 0.00000001 ), 
			ST_ClosestPoint(r.geom, p.geom)
		) AS inters
	FROM starting_points p
	LEFT JOIN routes r ON ST_DWithin(p.geom, r.geom, 0.001)
	WHERE 
			r.geom IS NOT NULL
		AND NOT ST_IsEmpty(r.geom)
	ORDER BY
		p.osm_id,
		ST_Distance(p.geom, r.geom, true)
),
joined_intersection AS (
	SELECT
		coalesce(i.intersected_osm_id, si.intersected_osm_id) AS intersected_osm_id,
		coalesce(i.inters, si.inters) AS inters
	FROM intersections i
	FULL OUTER JOIN starting_point_intersections si ON null = true
),
to_split AS (			-- All routed that needs to be splitted and point where the split will be applied
	SELECT i.inters, r1.*
	FROM joined_intersection i
	LEFT JOIN routes r1 ON i.intersected_osm_id = r1.osm_id
	WHERE
			ST_Distance(ST_StartPoint(r1.geom), i.inters, true) > 0.0001
		AND	ST_Distance(ST_EndPoint(r1.geom), i.inters, true) > 0.0001
),
expanded_to_split AS (		-- If one route need to be splitted by other route multiple times, create one record for each split point
	SELECT
		s.osm_id,
		ST_Transform(ST_AsEWKT((ST_Dump(s.inters)).geom), 4326) AS inters,
		ST_GeometryType(ST_AsEWKT((ST_Dump(s.inters)).geom)) AS inters_type,
		s.geom,
		s.highway,
		s.name,
		s.surface,
		s.tracktype
	FROM to_split s
),
unioned_split_points AS (	-- All points that split one route are joined to one multi-geometry
	SELECT 
		s.osm_id,
		s.geom,
		ST_Union(s.inters) AS union
	FROM expanded_to_split s
	WHERE s.inters_type = 'ST_Point'
	GROUP BY s.osm_id, s.geom
),
new_routes AS (
	SELECT
		u.osm_id,
		ST_Transform(ST_AsEWKT((ST_Dump(ST_Split(ST_Snap(u.geom, u.union, 0.001), u.union))).geom), 4326) AS geom,
		r.highway,
		r.name, 
		r.surface,
		r.tracktype
	FROM unioned_split_points u					-- Add data those were lost during transformation
	LEFT JOIN routes r ON u.osm_id = r.osm_id
),
sth_1 AS (								-- Delete routes that were splitted
	DELETE
	FROM routes r
	WHERE r.osm_id NOT IN(
		SELECT r.osm_id
		FROM routes r
		LEFT JOIN new_routes nr ON r.osm_id = nr.osm_id
		WHERE nr.osm_id IS NULL
	)
)
INSERT INTO routes(osm_id, geom, highway, name, surface, tracktype)	-- Insert splitted routes
	SELECT *
	FROM new_routes;

WITH accessible_areas AS (						-- Delete not acessible and not relevant routes for navigation
	SELECT ST_Union(ST_Buffer(p.geom, 0.004)) AS geom 
	FROM trails t
	FULL OUTER JOIN starting_points p ON p.osm_id = t.id
),
accessible_areas_routes AS (
	SELECT r.*
	FROM 
		routes r
	INNER JOIN accessible_areas aca ON ST_Intersects(r.geom, aca.geom)
),
accessible_trails AS (
	SELECT
		r.id,
		unnest(r.parts) AS line_osm_id_of_trail_part		-- rels.tags array to rows
	FROM public.planet_osm_rels r
	WHERE 
			'colour' = ANY(r.tags)
		AND	'hiking' = ANY(r.tags)
),
accessible_trails_routes AS (
	SELECT r.*
	FROM routes r
	LEFT JOIN accessible_trails act ON r.osm_id = act.line_osm_id_of_trail_part
	WHERE 
		act.line_osm_id_of_trail_part IS NOT NULL
)
DELETE 
FROM routes r
WHERE r.osm_id NOT IN (
	SELECT coalesce(at.osm_id, aa.osm_id) AS osm_id
	FROM accessible_trails_routes at
	FULL OUTER JOIN accessible_areas_routes aa ON at.osm_id = aa.osm_id
);
---------------------------------------------------------------------------------------------------

ALTER TABLE routes
	ADD COLUMN source bigint,
	ADD COLUMN target bigint,
	ADD COLUMN distance float,
	ADD COLUMN color text,
	ADD COLUMN id bigint GENERATED BY DEFAULT AS IDENTITY;

UPDATE routes SET distance = ST_Length(geom, true);

WITH routes_color AS (
	SELECT
		r.tags[array_position(r.tags, 'colour') + 1] AS color,
		unnest(r.parts)  line_osm_id_of_trail_part		-- rels.tags array to rows
	FROM public.planet_osm_rels r
	WHERE 
			'colour' = ANY(r.tags)
		AND	'hiking' = ANY(r.tags)
)
UPDATE routes r
SET color = c.color
	FROM (
		SELECT 
			line_osm_id_of_trail_part,
			array_agg(color) AS color
		FROM routes_color
		GROUP BY line_osm_id_of_trail_part
	) AS c
	WHERE r.osm_id = c.line_osm_id_of_trail_part;

SELECT pgr_createTopology('routes', 0.000001, 'geom', 'id', 'source', 'target', 'true', true);

ALTER TABLE starting_points
	ADD COLUMN nearest_point bigint,
	ADD COLUMN nearest_point_dstance float,
	ADD COLUMN nearest_point_route geometry;

WITH areas_around_starting_points AS (
	SELECT ST_Union(ST_Buffer(p.geom, 0.0005)) AS geom 
	FROM trails t
	FULL OUTER JOIN starting_points p ON p.osm_id = t.id
),
routes_around_starting_points AS (
	SELECT r.*
	FROM routes r
	INNER JOIN areas_around_starting_points aasp ON ST_Intersects(r.geom, aasp.geom)
),
new_starting_points AS (
	SELECT
		DISTINCT ON (p.osm_id) p.osm_id,
		p.name,
		p.type,
		p.geom,
		(SELECT id FROM routes_vertices_pgr v ORDER BY ST_Distance(v.the_geom, p.geom) LIMIT 1 ) AS nearest_point,
		ST_Distance(r.geom, p.geom, true) AS nearest_point_dstance,
		ST_MakeLine(ST_ClosestPoint(r.geom, p.geom), p.geom) AS nearest_point_route
	FROM starting_points p
	LEFT JOIN routes r ON ST_DWithin(p.geom, r.geom, 0.001)
	WHERE r.geom IS NOT NULL
	ORDER BY 
		p.osm_id,
		ST_Distance(p.geom, r.geom, true)
)
INSERT INTO starting_points (osm_id, name, type, geom, nearest_point, nearest_point_dstance, nearest_point_route)
	SELECT *
	FROM new_starting_points;

DELETE 
FROM starting_points
WHERE nearest_point_dstance IS NULL;

CREATE OR REPLACE FUNCTION route_to_start_point(source_point bigint, target_point_list bigint[])
RETURNS TABLE(
	seq integer, path_seq integer, end_vid bigint, node bigint, edge bigint, cost double precision, agg_cost double precision,
	osm_id bigint, geom geometry, highway text, name text, surface text, tracktype text, source bigint, target bigint, distance float, color text, id bigint
) AS
$$
  SELECT *
	FROM
		pgr_dijkstra(
			'SELECT
				id::integer AS id,
				source::integer,
				target::integer,
				distance::double precision AS cost,
				geom
			FROM routes',
 			source_point,
			target_point_list,
			false
		) AS rr
	LEFT JOIN routes r ON r.id = rr.edge
$$
LANGUAGE sql;

CREATE OR REPLACE FUNCTION find_best_route(source_point bigint, target_point_list bigint[])
RETURNS TABLE(
	seq integer, path_seq integer, end_vid bigint, node bigint, edge bigint, cost double precision, agg_cost double precision,
	osm_id bigint, geom geometry, highway text, name text, surface text, tracktype text, source bigint, target bigint, distance float, color text, id bigint
) AS
$$
	SELECT *
	FROM route_to_start_point(source_point, target_point_list)
	WHERE end_vid IN (
		SELECT end_vid			-- Choose the option with the less agg_cost
		FROM route_to_start_point(source_point, target_point_list)
		GROUP BY end_vid
		ORDER BY max(agg_cost) ASC
		LIMIT 1
	)
$$
LANGUAGE sql;

CREATE OR REPLACE FUNCTION find_route_to_point(lon float, lat float, end_point_types text[])
RETURNS TABLE( path_seq integer, osm_id bigint, geom geometry, highway text, name text, surface text, tracktype text, color text, distance float ) AS
$$
	WITH starting_points_ids AS (		-- All starting points ids as array
		SELECT array_agg(p.nearest_point) AS ids
		FROM starting_points p
		WHERE p.type = ANY(end_point_types)
	),
	selected_point AS (					-- Just selected point as geometry
		SELECT ST_SetSRID(ST_Point(lon, lat), 4326) AS geom
	),
	nearest_route AS (					-- Nearest route to selected point
		SELECT
			ST_Distance(r.geom, p.geom, true) AS distance_from_route,
			p.geom AS point_geom,
				ST_Intersection( 
				ST_Snap( r.geom, ST_ClosestPoint(r.geom, p.geom), 0.00000001 ), 
				ST_ClosestPoint(r.geom, p.geom)
			) AS intersection_point,
			r.*
		FROM 
			routes r,
			selected_point p
		ORDER BY 1 ASC
		LIMIT 1
	),
	split_nearest_route AS (			-- Split nearest route by selected point 
		SELECT
			n.*,
			ST_Transform(ST_AsEWKT((ST_Dump(ST_Split(ST_Snap(n.geom, n.intersection_point, 0.001), n.intersection_point))).geom), 4326) AS split_geom,
			ST_Length(ST_Transform(ST_AsEWKT((ST_Dump(ST_Split(ST_Snap(n.geom, n.intersection_point, 0.001), n.intersection_point))).geom), 4326), true) AS split_distance,
			ST_Distance(ST_Transform(ST_AsEWKT((ST_Dump(ST_Split(ST_Snap(n.geom, n.intersection_point, 0.001), n.intersection_point))).geom), 4326), v1.the_geom, true) AS distance_from_source_point,
			ST_Distance(ST_Transform(ST_AsEWKT((ST_Dump(ST_Split(ST_Snap(n.geom, n.intersection_point, 0.001), n.intersection_point))).geom), 4326), v2.the_geom, true) AS distance_from_target_point
		FROM nearest_route n
		LEFT JOIN routes_vertices_pgr v1 ON n.source = v1.id
		LEFT JOIN routes_vertices_pgr v2 ON n.target = v2.id
	),									-- Final nearest route split (reduced and redefined colum names)
	final_nearest_route_split AS (
		SELECT 
			n.osm_id,
			n.distance_from_route AS distance_from_selected_point,
			n.split_distance AS distance,
			n.point_geom AS selected_point_geom,
			n.intersection_point AS intersection_point_geom,
			n.split_geom AS geom,
			n.highway,
			n.name,
			n.surface,
			n.tracktype,
			n.color,
			n.id,
			CASE
				WHEN distance_from_source_point = 0 THEN n.source
				ELSE n.target
			END AS pg_routing_point_id
		FROM split_nearest_route n
	),
	shortest_route AS (
		SELECT
			pg_routing_point_id,
			(
				SELECT (max(agg_cost) + r.distance) FROM find_best_route(r.pg_routing_point_id, (SELECT * FROM starting_points_ids))
			) AS final_distance
		FROM final_nearest_route_split r
		ORDER BY final_distance ASC
		LIMIT 1
	)
	SELECT 
		coalesce(r.path_seq, 0) AS path_seq,
		coalesce(r.osm_id, sr.osm_id) AS osm_id,
		coalesce(r.geom, sr.geom) AS geom,
		coalesce(r.highway, sr.highway) AS highway,
		coalesce(r.name, sr.name) AS name,
		coalesce(r.surface, sr.surface) AS surface,
		coalesce(r.tracktype, sr.tracktype) AS tracktype,
		coalesce(r.color, sr.color) AS color,
		coalesce(r.distance, sr.distance) AS distance
	FROM find_best_route((SELECT pg_routing_point_id FROM shortest_route), (SELECT * FROM starting_points_ids)) AS r
	FULL OUTER JOIN (SELECT * FROM final_nearest_route_split WHERE pg_routing_point_id = (SELECT pg_routing_point_id FROM shortest_route)) sr ON false
$$
LANGUAGE sql;
