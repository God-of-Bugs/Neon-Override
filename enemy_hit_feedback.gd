class_name EnemyHitFeedback
extends RefCounted

const SAMPLE_RATE: int = 22050
const SOUND_DURATION: float = 0.12
const SPARK_COUNT: int = 20

static func configure_sparks(particles: GPUParticles3D) -> void:
	var process_material: ParticleProcessMaterial = ParticleProcessMaterial.new()
	process_material.direction = Vector3(0.0, 0.15, -1.0)
	process_material.spread = 180.0
	process_material.initial_velocity_min = 2.5
	process_material.initial_velocity_max = 5.5
	process_material.gravity = Vector3(0.0, -5.0, 0.0)
	process_material.scale_min = 0.035
	process_material.scale_max = 0.075
	process_material.color = Color(1.0, 0.48, 0.08, 1.0)
	particles.process_material = process_material
	particles.draw_pass_1 = _make_spark_mesh()
	particles.amount = SPARK_COUNT
	particles.lifetime = 0.32
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.emitting = false
	particles.local_coords = true
	particles.visibility_aabb = AABB(Vector3(-1.5, -1.5, -1.5), Vector3(3.0, 3.0, 3.0))
	particles.position = Vector3(0.0, 1.0, 0.0)

static func make_hit_sound() -> AudioStreamWAV:
	var audio: AudioStreamWAV = AudioStreamWAV.new()
	var pcm: PackedByteArray = PackedByteArray()
	var sample_count: int = int(SAMPLE_RATE * SOUND_DURATION)
	pcm.resize(sample_count * 2)
	for index: int in range(sample_count):
		var time: float = float(index) / SAMPLE_RATE
		var envelope: float = exp(-time * 32.0)
		var frequency: float = lerpf(980.0, 410.0, time / SOUND_DURATION)
		var body: float = sin(TAU * frequency * time) * envelope
		var transient: float = sin(TAU * 3100.0 * time) * exp(-time * 105.0) * 0.35
		var value: int = clampi(int((body * 0.6 + transient) * 20000.0), -32768, 32767)
		var unsigned_sample: int = value & 0xffff
		pcm[index * 2] = unsigned_sample & 0xff
		pcm[index * 2 + 1] = (unsigned_sample >> 8) & 0xff
	audio.data = pcm
	audio.format = AudioStreamWAV.FORMAT_16_BITS
	audio.mix_rate = SAMPLE_RATE
	audio.stereo = false
	return audio

static func _make_spark_mesh() -> QuadMesh:
	var mesh: QuadMesh = QuadMesh.new()
	mesh.size = Vector2(0.11, 0.035)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.58, 0.12, 1.0)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.35, 0.04, 1.0)
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.vertex_color_use_as_albedo = true
	mesh.material = material
	return mesh
