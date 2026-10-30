#!/usr/bin/env bash
# Uso: annotate_log.sh <livello: error|warning|notice> <titolo> <file> [ultime_righe]
# Pubblica la coda di un log come annotazione del check: cosi' l'esito e' leggibile
# anche dall'API pubblica, senza scaricare i log del job.
level="$1"; title="$2"; file="$3"; lines="${4:-60}"
[ -f "$file" ] || exit 0
body="$(tail -n "$lines" "$file")"
body="${body//'%'/'%25'}"
body="${body//$'\r'/'%0D'}"
body="${body//$'\n'/'%0A'}"
echo "::${level} title=${title}::${body:0:60000}"
