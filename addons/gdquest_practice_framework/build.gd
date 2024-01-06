#!/usr/bin/env -S godot --headless --script
## Build script that converts solutions into practices. On Linux run with:
##
## [codeblock]
## # might need to run:
## chmod +x build.gd
## ./build.gd
## [/codeblock]
##
## The build script also processes practice code lines by replacing them with the given
## comments at the end of the line in [b]GDScript[/b] files.
##
## [codeblock]
## position += delta * velocity # position
## [/codeblock]
##
## Results in the following practice code:
##
## [codeblock]
## position
## [/codeblock]
##
## In some cases we want to remove the line completely for more complex code. Empty comments at
## the end of the line result in deletion of the line in the practice GDScript file.
##
## Furthermore, we can use a special syntax like [code]# >[/code] and [code]# <[/code] to indent
## and respectively dedent the given line of code in the practice script, otherwise the indentation
## is preserved:
##
## [codeblock]
## func generate_gems(columns: int, rows: int) -> void:
##     # Add two nested loops to generate cell coordinates.
##     # Generate the columns with the first loop and the rows with the second.
##
##     # You'll need to indent the lines below to be inside the inner loop block.
##     # You can select the lines with the mouse and press Tab to do so.
##     # Update the cell value to represent the cell coordinates on each loop iteration.
##     for column in range(columns): #
##         for row in range(rows): #
##             var cell := Vector2(column, row) # << var cell := Vector2(0, 0)
##             generate_one_gem(cell) # << generate_one_gem(cell)
## [/codeblock]
##
## Results in the following practice code:
##
## [codeblock]
## func generate_gems(columns: int, rows: int) -> void:
##     # Add two nested loops to generate cell coordinates.
##     # Generate the columns with the first loop and the rows with the second.
##
##     # You'll need to indent the lines below to be inside the inner loop block.
##     # You can select the lines with the mouse and press Tab to do so.
##     # Update the cell value to represent the cell coordinates on each loop iteration.
##     var cell := Vector2(0, 0)
##     generate_one_gem(cell)
## [/codeblock]
##
## The build script [b]skips[/b] solutions that contain only one GDScript script file
## with the same name as the solution folder and a [code]metadata[/code] variable:
##
## [codeblock]
## # e.g. file path: res://solutions/some_practice/some_practice.gd
## var metadata := PracticeMetadata.new("Test Solution", "TEST_SOLUTION_ID") #
## [/codeblock]
##
## The build script [b]fails[/b] if there are solutions with no [code]metadata[/code] variable.[br]
## [br]
## [b]Note[/b] that:[br]
## - Only-comment lines are also preserved in the practice.[br]
## - The special [code]<[/code] and [code]>[/code] symbols can be repeated multiple times.
extends SceneTree

const Paths := preload("paths.gd")
const Utils := preload("utils.gd")

const DENTS := {"<": -1, ">": 1}

var regex_line := RegEx.create_from_string("^(\\h*)(.*)#\\h*(.*)$")
var regex_shift := RegEx.create_from_string("^([<>]+)\\h*(.*)")


func _init() -> void:
	if "--script" in OS.get_cmdline_args():
		for dir_name in DirAccess.get_directories_at(Paths.SOLUTIONS_PATH):
			build_solution(dir_name)
		quit()


func build_solution(dir_name: StringName, is_forced := false) -> void:
	print_rich("Building [b]%s[/b]..." % dir_name)
	var solution_dir_path := Paths.SOLUTIONS_PATH.path_join(dir_name)
	var solution_file_paths := Utils.fs_find("*", solution_dir_path)
	var solution_main_path := solution_dir_path.path_join("%s.gd" % dir_name)
	var solution_main: Object = load(solution_main_path).new()
	var log_message := "\t%s...%s"
	if not "metadata" in solution_main:
		print_rich(log_message % [solution_main_path, "[color=red]FAIL[/color]"])
		quit()
		return
	elif solution_file_paths.all(func(p: String) -> bool: return p == solution_main_path):
		print_rich(log_message % [solution_main_path, "[color=orange]SKIP[/color]"])
		return

	solution_file_paths.assign(
		solution_file_paths.filter(
			func(x: String) -> bool: return not (
				x.ends_with("_test.gd") or x.ends_with("_diff.gd") or x.get_extension() == "import"
			)
		)
	)

	var solution_diff_path := solution_dir_path.path_join("%s_diff.gd" % dir_name)
	var solution_diff: GDScript = null
	if FileAccess.file_exists(solution_diff_path):
		solution_diff = load(solution_diff_path)

	for solution_file_path in solution_file_paths:
		var extension := solution_file_path.get_extension()
		var practice_file_path: String = solution_file_path.replace(
			Paths.SOLUTIONS_PATH, Paths.PRACTICES_PATH
		)
		var practice_file_modified_time := FileAccess.get_modified_time(practice_file_path)
		if (
			(
				FileAccess.file_exists(practice_file_path)
				and practice_file_modified_time > FileAccess.get_modified_time(solution_file_path)
				and practice_file_modified_time > FileAccess.get_modified_time(solution_diff_path)
			)
			and not is_forced
		):
			print_rich(log_message % [practice_file_path, "[color=orange]SKIP[/color]"])
			continue

		DirAccess.make_dir_recursive_absolute(practice_file_path.get_base_dir())
		if extension == "tscn" and solution_diff != null:
			var solution_scene: Node = load(solution_file_path).instantiate()
			var func_name := solution_file_path.get_file().get_basename()
			if func_name in solution_diff:
				solution_diff.call(func_name, solution_scene)
				var practice_packed_scene := PackedScene.new()
				practice_packed_scene.pack(solution_scene)
				ResourceSaver.save(practice_packed_scene, practice_file_path)
				print_rich(log_message % [solution_file_path, "[color=blue]DIFF[/color]"])

		else:
			DirAccess.copy_absolute(solution_file_path, practice_file_path)
			print_rich(log_message % [practice_file_path, "[color=green]COPY[/color]"])

		if extension in ["gd", "tscn"]:
			var contents := FileAccess.get_file_as_string(practice_file_path)
			if extension == "gd":
				contents = _process_gd(contents)
			contents = contents.replace(Paths.SOLUTIONS_PATH, Paths.PRACTICES_PATH)
			FileAccess.open(practice_file_path, FileAccess.WRITE).store_string(contents)
			print_rich(log_message % [practice_file_path, "[color=yellow]PROCESS[/color]"])


func _process_gd(contents: String) -> String:
	var partial_result := []
	for line in contents.split("\n"):
		var processed := _process_line(line)
		if processed.do_skip:
			continue
		partial_result.push_back(processed.line)
	return "\n".join(partial_result).strip_edges() + "\n"


func _process_line(line: String) -> Dictionary:
	var result := {line = line, do_skip = false}
	var regex_line_match := regex_line.search(line)
	if regex_line_match != null and not regex_line_match.strings[2].is_empty():
		result.line = _process_tabs(
			regex_line_match.strings[1], regex_line_match.strings[3].strip_edges()
		)
		result.do_skip = not line.strip_edges().is_empty() and result.line.strip_edges().is_empty()
	return result


func _process_tabs(prefix: String, line: String) -> String:
	var tabs := prefix.count("\t")
	var regex_shift_match := regex_shift.search(line)
	if regex_shift_match != null:
		for shift in regex_shift_match.strings[1]:
			tabs += DENTS[shift]
		line = regex_shift_match.strings[2]
	return "\t".repeat(tabs) + line
