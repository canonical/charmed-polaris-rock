# Apache Polaris rock

[![Container Registry](https://img.shields.io/badge/Container%20Registry-published-blue)](https://github.com/canonical/polaris-rock/pkgs/container/polaris)
[![Release](https://github.com/canonical/polaris-rock/actions/workflows/publish.yaml/badge.svg)](https://github.com/canonical/polaris-rock/actions/workflows/publish.yaml)

This repository contains the packaging metadata for creating a Apache Polaris rock (OCI compliant image).

For more information on rocks, visit the [rockcraft Github](https://github.com/canonical/rockcraft).

## Building the ROCK

The steps outlined below are based on the assumption that you are building the rock with the latest LTS of Ubuntu.\
If you are using another version of Ubuntu or another operating system, the process may be different.
To avoid any issue with other operating systems you can simply build the image with [multipass](https://multipass.run/):

```bash
sudo snap install multipass
multipass launch 26.04 -n rock-dev
multipass shell rock-dev
```

### Clone repository

```bash
git clone https://github.com/canonical/polaris-rock.git
cd polaris-rock
```

### Installing tooling

```bash
sudo snap install rockcraft --classic
sudo apt install podman
```

### Packing and Running the ROCK

```bash
rockcraft pack
podman load < polaris_1.5.0_amd64.rock
podman run -it --rm --name polaris --entrypoint /bin/bash localhost/1.5.0:latest
```

## Licence statement

Apache Polaris rock is free software, distributed under the [Apache Software License, version 2.0](licenses/LICENSE-rock).

## Trademark Notice

Apache®, Apache Polaris™, Apache Iceberg™, Apache Spark™ are either registered trademarks or trademarks of the Apache Software Foundation in the United States and/or other countries.
