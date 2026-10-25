// ark_native 的 GDExtension 入口（docs/101 §4.7）：注册 EnemyCore、EnemyRender（docs/50 §28）。entry_symbol 与 game/bin/ark_native.gdextension 一致
#include <gdextension_interface.h>

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

#include "enemy_core_bind.h"
#include "enemy_render_bind.h"

using namespace godot;

static void initialize_ark_native(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(EnemyCore);
	GDREGISTER_CLASS(EnemyRender);
}

static void uninitialize_ark_native(ModuleInitializationLevel p_level) {
}

extern "C" {
GDExtensionBool GDE_EXPORT ark_native_init(GDExtensionInterfaceGetProcAddress p_get_proc_address, GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
	::godot::GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
	init_obj.register_initializer(initialize_ark_native);
	init_obj.register_terminator(uninitialize_ark_native);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_obj.init();
}
}
