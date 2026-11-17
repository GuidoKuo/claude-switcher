"""Run the real installer against an isolated fake HOME and fake system root."""
import os, shutil, subprocess, tempfile, unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
class InstallTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name); self.home=self.root/'home'; self.home.mkdir()
        self.sys=self.root/'system'; (self.sys/'Applications/Claude.app').mkdir(parents=True)
        self.kit=self.root/'kit'; self.kit.mkdir(); self.bin=self.root/'bin'; self.bin.mkdir()
        for n in ('安装.command','卸载.command','manage.sh'): shutil.copy2(ROOT/'soft-router'/n,self.kit/n)
        manage=self.kit/'manage.sh'; manage.write_text(manage.read_text().replace('SYSTEM=""; ADMIN="sudo"', 'SYSTEM="$CS_TEST_ROOT"; ADMIN=""'))
        shutil.copy2(ROOT/'core/claude-switch.sh',self.kit/'claude-switch.sh'); shutil.copy2(ROOT/'core/stun-probe.py',self.kit/'stun-probe.py')
        app=self.kit/'Claude切换器.app/Contents/MacOS'; app.mkdir(parents=True); (app/'ClaudeSwitcher').write_text('stub'); (app/'ClaudeSwitcher').chmod(0o755)
        cmds={
          'uname': 'case "$1" in -s) echo Darwin;; -m) echo x86_64;; esac',
          'route': 'echo "gateway: 94.83.87.2"; echo "interface: en0"',
          'ipconfig': 'echo 94.83.87.52', 'dig': 'echo 198.18.1.1',
          'ditto': 'cp -pR "$1" "$2"',
          'launchctl': '''key=$(echo "$2" | tr / _); f="$HOME/services/$key"; case "$1" in
print) if [ -f "$f" ]; then echo loaded; else echo 'Bad request.' >&2; exit 1; fi;;
bootout) [ "${FAIL_STOP:-}" != 1 ] || exit 1; rm -f "$f";; esac''',
        }
        for n,body in cmds.items():
            f=self.bin/n; f.write_text('#!/bin/sh\n'+body+'\n'); f.chmod(0o755)
        self.env={**os.environ,'HOME':str(self.home),'PATH':f'{self.bin}:/usr/bin:/bin:/usr/sbin:/sbin', 'CS_TEST_ROOT':str(self.sys)}
    def old(self):
        def put(path, content): path.parent.mkdir(parents=True,exist_ok=True); path.write_text(content)
        put(self.home/'.claude-switcher/accounts/A/session', 'PRIVATE')
        put(self.home/'.claude-switcher/current', 'A\n')
        put(self.home/'.claude-switcher/cli-accounts/B/token', 'CLI')
        put(self.home/'.claude-switcher/keep-stage/pending', 'PENDING')
        put(self.home/'.local/bin/claude-switch.sh','OLD')
        put(self.home/'Library/LaunchAgents/local.claude-update.plist','OLD AGENT')
        put(self.sys/'Library/LaunchDaemons/local.claude-bodyguard.plist','OLD DAEMON')
        for name in ('system_local.claude-bodyguard','gui_'+str(os.getuid())+'_local.claude-update'):
            put(self.home/'services'/name,'loaded')
    def run_kit(self,name,inp,**extra):
        return subprocess.run(['/bin/bash',str(self.kit/name)], input=inp, capture_output=True,text=True,env={**self.env,**extra},timeout=30)
    def test_migrate_preserves_and_replaces(self):
        self.old(); p=self.run_kit('安装.command','1\nSG\nYES\n\n'); self.assertEqual(p.returncode,0,p.stdout+p.stderr)
        base=self.home/'.claude-switcher'; self.assertEqual((base/'accounts/A/session').read_text(),'PRIVATE'); self.assertEqual((base/'keep-stage/pending').read_text(),'PENDING')
        self.assertEqual((base/'cli-accounts/B/token').read_text(),'CLI'); self.assertIn('COUNTRY_TARGET="SG"',(self.home/'.local/bin/claude-switch.sh').read_text())
        self.assertFalse((self.sys/'Library/LaunchDaemons/local.claude-bodyguard.plist').exists()); self.assertFalse((self.home/'services/system_local.claude-bodyguard').exists())
        b=list((self.home/'.claude-switcher-backups').glob('old.*')); self.assertEqual(len(b),1); self.assertEqual((b[0]/'user/.claude-switcher/accounts/A/session').read_text(),'PRIVATE')
    def test_fresh_keeps_backup_not_active(self):
        self.old(); p=self.run_kit('安装.command','2\nUS\nYES\n\n'); self.assertEqual(p.returncode,0,p.stdout+p.stderr)
        self.assertFalse((self.home/'.claude-switcher/accounts/A/session').exists()); self.assertTrue(list((self.home/'.claude-switcher-backups').glob('old.*/user/.claude-switcher/accounts/A/session')))
    def test_cancel_changes_nothing(self):
        self.old(); p=self.run_kit('安装.command','3\n'); self.assertNotEqual(p.returncode,0); self.assertEqual((self.home/'.local/bin/claude-switch.sh').read_text(),'OLD'); self.assertTrue((self.home/'services/system_local.claude-bodyguard').exists())
    def test_failed_service_stop_prevents_moves(self):
        self.old(); p=self.run_kit('安装.command','1\nUS\nYES\n',FAIL_STOP='1'); self.assertNotEqual(p.returncode,0); self.assertEqual((self.home/'.local/bin/claude-switch.sh').read_text(),'OLD'); self.assertTrue((self.sys/'Library/LaunchDaemons/local.claude-bodyguard.plist').exists())
    def test_uninstall_backup_and_preserve_claude(self):
        self.old(); p=self.run_kit('卸载.command','YES\n\n'); self.assertEqual(p.returncode,0,p.stdout+p.stderr)
        self.assertFalse((self.home/'.local/bin/claude-switch.sh').exists()); self.assertTrue((self.sys/'Applications/Claude.app').exists()); self.assertTrue(list((self.home/'.claude-switcher-backups').glob('old.*/user/.claude-switcher/accounts/A/session')))
