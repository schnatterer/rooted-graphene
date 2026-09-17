#!/usr/bin/env python3

import argparse
from collections.abc import Iterable
import functools
import logging
from pathlib import Path, PurePosixPath
import shutil
import sys
from typing import override

patcher_dir = Path(__file__).resolve().parent / '.tmp' / 'my-avbroot-setup'
sys.path.insert(0, str(patcher_dir))

import patch as avbroot_patch
from lib import modules
from lib.filesystem import CpioFs, ExtFs
from lib.modules import MissingArgs, Module, ModuleRequirements

logger = logging.getLogger(__name__)


class APatchManagerModule(Module):
    NAME = 'apatch-manager'

    @classmethod
    @override
    def add_args(cls, parser: argparse.ArgumentParser):
        parser.add_argument(
            '--module-apatch-manager',
            type=Path,
            help='APatch manager APK to install as a system app',
        )

    def __init__(self, args: argparse.Namespace) -> None:
        apk: Path | None = args.module_apatch_manager
        if apk is None:
            raise MissingArgs()
        self.apk = apk

    @override
    def requirements(self) -> ModuleRequirements:
        return ModuleRequirements(
            boot_images=set(),
            ext_images={'system'},
            selinux_patching=False,
        )

    @override
    def inject(
        self,
        boot_fs: dict[str, CpioFs],
        ext_fs: dict[str, ExtFs],
        sepolicies: Iterable[Path],
    ) -> None:
        logger.info('Injecting APatch manager: %s', self.apk)

        destination = PurePosixPath('system/app/APatch/APatch.apk')
        system_fs = ext_fs['system']
        system_fs.mkdir(destination.parent, mode=0o755, parents=True, exist_ok=True)

        with self.apk.open('rb') as f_in, system_fs.open(destination, 'wb', mode=0o644) as f_out:
            shutil.copyfileobj(f_in, f_out)


original_all_modules = modules.all_modules


@functools.cache
def all_modules() -> list[type[Module]]:
    return [*original_all_modules(), APatchManagerModule]


modules.all_modules = all_modules

if __name__ == '__main__':
    avbroot_patch.main()
