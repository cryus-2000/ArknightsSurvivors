import sys; sys.path.insert(0, 'tools'); import godot_runner as GR
args = sys.argv[2:]
out, err, to = GR.run_godot([GR.find_godot(), '--headless', '--path', 'game', '--'] + args, 1500)
open(sys.argv[1], 'w').write(out + '\n=====STDERR=====\n' + err + ('\nTIMEOUT' if to else ''))
