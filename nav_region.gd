class_name NavRegion
extends NavigationRegion3D

## Bakes the navigation mesh from the CSG level geometry at startup, so the
## enemies always path against the level as it currently stands. Re-run this
## bake (or use the editor's Bake button) whenever the geometry changes.


func _ready() -> void:
	bake_finished.connect(_on_bake_finished)
	# CSG geometry is finalised a frame or two after entering the tree, so wait
	# before baking or the navmesh comes out empty.
	await get_tree().physics_frame
	await get_tree().physics_frame
	bake_navigation_mesh()


func _on_bake_finished() -> void:
	print("[NavRegion] baked navigation mesh: ",
		navigation_mesh.get_polygon_count(), " polygons, ",
		navigation_mesh.get_vertices().size(), " vertices")
	var err: int = ResourceSaver.save(navigation_mesh, "res://navmesh.tres")
	print("[NavRegion] ResourceSaver.save -> err=", err)
