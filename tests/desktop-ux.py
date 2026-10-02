#!/usr/bin/env python3
"""Startup project precedence and desktop actions, with isolated user state.

rhunpad: without arguments the scratchpad home (~/rhunpad) opens, with a new untitled
note when its own session has nothing open. Explicit folders and files win as before.
"""
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent
EXE = Path(os.environ.get('RHUN_TEST_EXE', ROOT / 'build/rhun')).resolve()

with tempfile.TemporaryDirectory(prefix='rhunpad-desktop-') as temporary:
    work = Path(temporary).resolve()
    project = work / 'project café with spaces'
    other = work / 'other'
    project.mkdir()
    other.mkdir()
    file = project / "file ' $test.txt"
    file.write_text('hello\n')
    config = work / 'config/rhunpad/config'
    config.parent.mkdir(parents=True)
    env = dict(os.environ, HOME=work.as_posix(), XDG_CONFIG_HOME=(work / 'config').as_posix(),
                XDG_STATE_HOME=(work / 'state').as_posix())

    def configure(tabs=True):
        # the interface the click coordinates of this test are written for
        config.write_text('[editor]\nfont_size = 14\nline_height = 150\n'
                          '[ui]\nsidebar = true\nagents_panel = true\n'
                          '[files]\nrestore_session = ' + str(tabs).lower() +
                          '\nautosave = false\n[updates]\ncheck = false\n[git]\nenabled = false\n')

    def run(paths=(), lines=('print-project', 'print-state', 'quit')):
        script = work / 'commands.rsc'
        script.write_text('\n'.join(lines) + '\n', encoding='utf-8')
        result = subprocess.run([str(EXE), *map(str, paths), '--headless', '1000x700',
                                 '--script', str(script)], cwd=other, env=env,
                                capture_output=True, timeout=20, check=True)
        return result.stdout.decode('utf-8')

    def check_project(output, name):
        assert f'project=~/{name}\n' in output, output

    def check_pad(output, tabs='1 '):
        assert 'project=~/rhunpad\n' in output, output
        assert f'tabs={tabs}' in output, output

    # A fresh start is the pad: its home exists and a new untitled note is open in it.
    output = run()
    check_pad(output)
    assert (work / 'rhunpad').is_dir()
    assert 'active=untitled ' in output, output
    print('ok   desktop/fresh-start-is-the-pad')

    # Notes are plain files the user owns: typed text names itself untitled-1.md at its first
    # autosave, and the pad's session brings it back with the same name.
    run((), ['type pad note', 'wait 1500', 'quit'])
    assert (work / 'rhunpad/untitled-1.md').read_text() == 'pad note\n', 'untitled note file'
    output = run()
    check_pad(output)
    assert 'active=untitled-1.md ' in output, output
    print('ok   desktop/pad-session-restored')

    # Explicit folders and files always win.
    check_project(run([other]), other.name)
    run([project, file])
    output = run([project])
    check_project(output, project.name)
    assert 'tabs=1 ' in output, output
    print('ok   desktop/explicit-folder-and-file-win')

    configure(tabs=False)
    run([project])
    output = run([project])
    check_project(output, project.name)
    assert 'tabs=0 ' in output, output
    print('ok   desktop/project-without-tab-restoration')

    # After working elsewhere, a start without arguments is back at the pad.
    run([other], [f'open {project.as_posix()}', 'quit'])
    check_pad(run())
    print('ok   desktop/back-to-the-pad')

    # Never open real desktop applications in the automated suite.
    if os.name != 'nt':
        bin_dir = work / 'bin'
        bin_dir.mkdir()
        opener = bin_dir / ('open' if sys.platform == 'darwin' else 'xdg-open')
        opener.write_text('#!/bin/sh\nprintf "%s\\n" "$@" >> "$RHUN_DESKTOP_LOG"\n')
        opener.chmod(0o755)
        log = work / 'opened'
        env.update(PATH=str(bin_dir) + os.pathsep + os.environ.get('PATH', ''),
                   RHUN_DESKTOP_LOG=str(log))
        run([project, file], ['cmd website', 'wait 200', 'cmd feedback', 'wait 200',
                              'cmd reveal_file', 'wait 200', 'quit'])
        expected = ['https://rhun.app', 'mailto:vlad@omniprag.com?subject=rhun%20feedback']
        expected += ['-R', file.as_posix()] if sys.platform == 'darwin' else [project.as_posix()]
        assert log.read_text().splitlines() == expected, log.read_text()
        print('ok   desktop/links-and-literal-file-path')

        log.unlink()
        with config.open('a') as settings:
            settings.write('[ui]\nagents_panel = false\n')
        run([project], ['cmd settings', 'click 300 202', 'wait 200',
                        'click 420 230', 'wait 200', 'quit'])
        assert log.read_text().splitlines() == [
            'https://rhun.app', 'mailto:vlad@omniprag.com?subject=rhun%20feedback'], log.read_text()
        print('ok   desktop/settings-links')

        # The menu operates on a directory as well as a file, with the same path rules.
        log.unlink()
        directory = project / 'a folder café'
        directory.mkdir()
        output = run([project], ['click 50 86 right', 'print-menu', 'click 110 265',
                                  'wait 200', 'quit'])
        label = 'Show in Finder' if sys.platform == 'darwin' else 'Open in File Manager'
        assert label in output, output
        expected = ['-R', directory.as_posix()] if sys.platform == 'darwin' else [project.as_posix()]
        assert log.read_text().splitlines() == expected, log.read_text()
        print('ok   desktop/directory-menu')
