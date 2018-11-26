SELECT *
FROM pg_stats
WHERE 
	(
		null_frac < 0.97
	)
	AND tablename = 'routes'
	AND attname NOT IN ('z_order', 'target', 'ref', 'layer', 'service', 'bicycle', 'bridge', 'foot', 'oneway', 'way')
	
-- osm_id, geom, source, target, distance, highway, name, surface, tracktype
