"""Synthetic network tests. No real network, root daemon or account data used."""
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

class RouterModeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.home = self.root / 'home'
        self.base = self.home / '.claude-switcher'
        self.base.mkdir(parents=True)
        (self.home / 'Library/Logs').mkdir(parents=True)
        (self.base / 'router-network').write_text('94.83.87.2\nen0\n94.83.87.52\n')
        self.bin = self.root / 'bin'; self.bin.mkdir()
        self.core = self.root / 'core.sh'
        text = (ROOT / 'core/claude-switch.sh').read_text().replace('PROXY_MODE="clash-verge"', 'PROXY_MODE="router"', 1)
        self.core.write_text(text); self.core.chmod(0o755)
        scripts = {
            'launchctl': '[ "${MOCK_GUARD:-0}" = 1 ] && exit 0; exit 1',
            'route': 'printf "gateway: %s\\ninterface: en0\\n" "${MOCK_GATEWAY:-94.83.87.2}"',
            'ipconfig': 'echo "${MOCK_IP:-94.83.87.52}"',
            'netstat': 'printf "Routing tables\\n%s\\n" "${MOCK_V6:-::1 lo0}"',
            'dig': 'echo "${MOCK_DNS:-198.18.1.94}"',
            'curl': '''echo called >> "$HOME/curl-was-called"
case "$*" in
  *cdn-cgi/trace*) printf 'ip=203.0.113.1\\nloc=US\\n';;
  *ipinfo.io*) echo '{"org":"test"}' ;;
  *) echo 200;;
esac''',
            'defaults': 'printf "en-US\\n"',
            'ifconfig': 'echo called >> "$HOME/ifconfig-was-called"; exit 1',
        }
        for name, body in scripts.items():
            file=self.bin/name; file.write_text('#!/bin/sh\n'+body+'\n'); file.chmod(0o755)
        self.env = dict(os.environ, HOME=str(self.home), PATH=f'{self.bin}:/usr/bin:/bin', LC_ALL='C')

    def run_core(self, command, **env):
        return subprocess.run(['/bin/bash',str(self.core),*command],env={**self.env,**env},capture_output=True,text=True,timeout=20)

    def test_ready_displays_limits_without_local_tun_or_daemon(self):
        p=self.run_core(['checkdetail'])
        log = self.base / "last-check.txt"
        debug = log.read_text() if log.exists() else "no last-check file"
        self.assertEqual(p.returncode,0,p.stdout+p.stderr+"\n"+debug)
        for item in ['代理内核=warn:', 'TUN网卡=skip:', '保镖=warn:', '规则置顶=warn:', 'WebRTC=warn:', 'DNS=warn:', 'IPv6=warn:']:
            self.assertIn(item,p.stdout)
        self.assertFalse((self.home/'ifconfig-was-called').exists())

    def test_existing_guard_blocks_before_network(self):
        p=self.run_core(['checkdetail'],MOCK_GUARD='1')
        self.assertNotEqual(p.returncode,0)
        self.assertIn('保镖',p.stdout)
        self.assertFalse((self.home/'curl-was-called').exists())

    def test_missing_baseline_blocks_before_network(self):
        (self.base/'router-network').unlink()
        p=self.run_core(['checkdetail'])
        self.assertNotEqual(p.returncode,0)
        self.assertFalse((self.home/'curl-was-called').exists())

    def test_wrong_gateway_blocks_before_http_and_switch(self):
        p=self.run_core(['switch','B'],MOCK_GATEWAY='94.83.87.1')
        self.assertNotEqual(p.returncode,0)
        self.assertFalse((self.home/'curl-was-called').exists())
        self.assertFalse((self.base/'current').exists())

    def test_changed_source_ip_blocks(self):
        p=self.run_core(['checkdetail'],MOCK_IP='94.83.87.65')
        self.assertNotEqual(p.returncode,0)
        self.assertFalse((self.home/'curl-was-called').exists())

    def test_ipv6_default_blocks_before_dns_and_http(self):
        p=self.run_core(['checkdetail'],MOCK_V6='default fe80::1 en0')
        self.assertNotEqual(p.returncode,0)
        self.assertIn('IPv6',p.stdout)
        self.assertFalse((self.home/'curl-was-called').exists())

    def test_non_fake_dns_blocks_before_http(self):
        p=self.run_core(['checkdetail'],MOCK_DNS='1.2.3.4')
        self.assertNotEqual(p.returncode,0)
        self.assertFalse((self.home/'curl-was-called').exists())

    def test_unsafe_actions_disabled(self):
        for args in (['update','--auto'],['fix'],['set-region'],['open-safe','https://example.com'],['set-client','auto']):
            with self.subTest(args=args):
                p=self.run_core(args)
                self.assertNotEqual(p.returncode,0,p.stdout+p.stderr)
                self.assertFalse((self.home/'curl-was-called').exists())

if __name__=='__main__': unittest.main()
