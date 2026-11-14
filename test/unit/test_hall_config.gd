extends GutTest
## Hall content configs: every main task lives in exactly one element, elements
## never span story days, every area has a wing, and validate_hall catches bad refs.

func test_every_task_in_exactly_one_element() -> void:
	assert_eq(ConfigDB.element_by_task.size(), ConfigDB.main_task_by_key.size())
	var seen := {}
	for id in ConfigDB.hall_elements:
		for key in ConfigDB.hall_elements[id]["tasks"]:
			assert_false(seen.has(key), "task in two elements: " + key)
			seen[key] = true
	assert_eq(seen.size(), ConfigDB.main_task_by_key.size())

func test_elements_never_span_days_and_have_three_looks() -> void:
	for id in ConfigDB.hall_elements:
		var row: Dictionary = ConfigDB.hall_elements[id]
		var days := {}
		for key in row["tasks"]:
			days[String(key).split("_")[0]] = true
		assert_eq(days.size(), 1, id)
		assert_between((row["tasks"] as Array).size(), 1, 4, id)
		assert_eq((row["looks"] as Array).size(), 3, id)
		assert_eq(row["looks"][0]["instruction"], null, id)

func test_all_47_wings_with_subrooms_covering_elements() -> void:
	for area in range(1, 48):
		assert_true(ConfigDB.hall_wings.has(area))
		for el in ConfigDB.area_elements[area]:
			assert_lt(int(el["subroom"]), (ConfigDB.hall_wings[area]["subrooms"] as Array).size())

func test_real_config_validates_clean() -> void:
	assert_eq(ConfigDB.validate_hall(ConfigDB.hall_wings.values(), ConfigDB.hall_elements.values(), ConfigDB.story_scenes.values()), [])

func test_validate_rejects_bad_scene_refs() -> void:
	var dir := "res://test/fixtures/hall_bad/"
	var wings: Array = ConfigDB.hall_wings.values()
	var elements: Array = ConfigDB.hall_elements.values()
	var scenes: Array = ConfigDB._read(dir + "curio_hall_story.json")
	var errors := ConfigDB.validate_hall(wings, elements, scenes)
	assert_eq(errors.size(), 2, str(errors))
	var joined := "\n".join(errors)
	assert_true(joined.contains("99_999"), joined)
	assert_true(joined.contains("imelda"), joined)

func test_validate_reports_malformed_scenes_without_crashing() -> void:
	var scenes: Array = [{"id": "no_trigger", "kind": "beat"}, {"id": "dup_el_scene", "kind": "beat", "trigger": "day:1", "lines": [{"text": "hi"}]}]
	var errors := ConfigDB.validate_hall(ConfigDB.hall_wings.values(), ConfigDB.hall_elements.values(), scenes)
	var joined := "\n".join(errors)
	assert_true(joined.contains("no_trigger: missing trigger"), joined)
	assert_true(joined.contains("dup_el_scene: speaker"), joined)

func test_validate_rejects_duplicate_element_ids() -> void:
	var elements: Array = ConfigDB.hall_elements.values()
	elements.append(elements[0])
	var errors := ConfigDB.validate_hall(ConfigDB.hall_wings.values(), elements, [])
	assert_true("\n".join(errors).contains("duplicate id"), str(errors))
