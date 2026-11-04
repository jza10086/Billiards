extends Node3D
## Authored pool table. Ball transforms use table-local X/Z coordinates.
@onready var camera: Camera3D = $TableCamera
@onready var world: WorldEnvironment = $Environment
@onready var sun: DirectionalLight3D = $Sun
@onready var rack: Node3D = $Balls
