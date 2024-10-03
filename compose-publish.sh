#!/bin/bash

add_layers_manifest=true
if [ "${OCI_COMPLIANT_APP}" == "1" ]; then
	add_layers_manifest=false
fi

composectl publish --layers-manifest=$add_layers_manifest $@
