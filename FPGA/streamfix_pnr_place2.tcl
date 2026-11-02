set project_dir [file dirname [file normalize [info script]]]
cd $project_dir
open_project audio_tone.gprj
set_option -top_module top
set_option -include_path [list "$project_dir/src" "$project_dir/src/tone" "$project_dir/src/drum/six" "$project_dir/src/ble" "$project_dir/src/filter" "$project_dir/src/adc" "$project_dir/src/music"]
set_option -output_base_name audio_tone_music_hall
set_option -use_cpu_as_gpio 1
set_option -use_sspi_as_gpio 1
set_option -place_option 2
set_option -route_option 2
run pnr
