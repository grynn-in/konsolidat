# Copyright (c) 2024 Open EPM Contributors
# SPDX-License-Identifier: MIT

import sys

from airbyte_cdk.entrypoint import launch
from .source import SourceErpnext


def run():
    source = SourceErpnext()
    launch(source, sys.argv[1:])


if __name__ == "__main__":
    run()
