#!/usr/bin/env bash
# Lihat ReplicaSet + nomor revisinya tanpa kena masalah glob zsh.
# Pakai: ./rs-revisi.sh [namespace]     (default: belajar)
set -euo pipefail

NS="${1:-belajar}"

kubectl get rs -n "$NS" -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.annotations.deployment\.kubernetes\.io/revision}{"\t"}{.spec.replicas}{"\t"}{.status.readyReplicas}{"\t"}{.spec.template.spec.containers[0].image}{"\n"}{end}'