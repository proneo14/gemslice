#!/bin/bash
export LD_LIBRARY_PATH=/opt/orcaslicer/bin:$LD_LIBRARY_PATH
export LC_ALL=C
exec xvfb-run -a /opt/orcaslicer/bin/orca-slicer "$@"
