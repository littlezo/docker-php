#!/usr/bin/env bash
set -Eeuo pipefail

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

versions=("$@")
if [ ${#versions[@]} -eq 0 ]; then
	versions=(*/)
	json='{}'
else
	json="$(<versions.json)"
fi
versions=("${versions[@]%/}")

for version in "${versions[@]}"; do
	rcVersion="${version%-rc}"
	export version rcVersion

	# scrape the relevant API based on whether we're looking for pre-releases
	if [ "$rcVersion" = "$version" ]; then
		apiUrl="https://www.php.net/releases/index.php?json&max=100&version=${rcVersion%%.*}"
		apiJqExpr='
			(keys[] | select(startswith(env.rcVersion))) as $version
			| [ $version, (
				.[$version].source[]
				| select(.filename | endswith(".xz"))
				|
					"https://www.php.net/distributions/" + .filename,
					"https://www.php.net/distributions/" + .filename + ".asc",
					.sha256 // ""
			) ]
		'
	else
		apiUrl='https://qa.php.net/api.php?type=qa-releases&format=json'
		apiJqExpr='
			(.releases // [])[]
			| select(.version | startswith(env.rcVersion))
			| [
				.version,
				.files.xz.path // "",
				"",
				.files.xz.sha256 // ""
			]
		'
	fi
	IFS=$'\n'
	possibles=($(
		curl -fsSL "$apiUrl" |
			jq --raw-output "$apiJqExpr | @sh" |
			sort -rV
	))
	unset IFS

	if [ "${#possibles[@]}" -eq 0 ]; then
		if [ "$rcVersion" = "$version" ]; then
			echo >&2
			echo >&2 "error: unable to determine available releases of $version"
			echo >&2
			exit 1
		else
			echo >&2 "warning: skipping/removing '$version' (does not appear to exist upstream)"
			json="$(jq <<<"$json" -c '.[env.version] = null')"
			continue
		fi
	fi

	# format of "possibles" array entries is "VERSION URL.TAR.XZ URL.TAR.XZ.ASC SHA256" (each value shell quoted)
	#   see the "apiJqExpr" values above for more details
	eval "possi=( ${possibles[0]} )"
	fullVersion="${possi[0]}"
	url="${possi[1]}"
	ascUrl="${possi[2]}"
	sha256="${possi[3]}"

	if ! wget -q --spider "$url"; then
		echo >&2 "error: '$url' appears to be missing"
		exit 1
	fi

	# if we don't have a .asc URL, let's see if we can figure one out :)
	if [ -z "$ascUrl" ] && wget -q --spider "$url.asc"; then
		ascUrl="$url.asc"
	fi

	variants='[]'
	# order here controls the order of the library/ file
	for suite in \
		bookworm \
		bullseye \
<<<<<<< HEAD
		alpine3.20 \
		alpine3.19 \
<<<<<<< HEAD
=======
		alpine3.18 \
<<<<<<< HEAD
<<<<<<< HEAD
<<<<<<< HEAD
		alpine3.16 \
>>>>>>> 8b7004a0 (fix 8.0 latest eol release)
=======
>>>>>>> 18f9a930 (remove 8.0 eol)
=======
		alpine3.16 \
>>>>>>> 94ac709b (Update 8.0)
=======
>>>>>>> 8d656cb0 (Remove 8.0 release EOL)
	; do
<<<<<<< HEAD
		for variant in cli apache fpm zts; do
			if [[ "$suite" = alpine* ]]; then
				if [ "$variant" = 'apache' ]; then
=======
		buster \
		alpine3.15; do
		for variant in cli zts; do
=======
		# https://github.com/docker-library/php/pull/1348
		if [ "$rcVersion" = '8.0' ] && [[ "$suite" = alpine* ]] && [ "$suite" != 'alpine3.16' ]; then
			continue
		fi
<<<<<<< HEAD
		for variant in cli zts swoole; do
>>>>>>> 1e7ad040 (feat: swoole)
			if [[ "$suite" = alpine* ]]; then
				if [ "$variant" = 'zts' ] && [[ "$rcVersion" != 7.* ]]; then
					# https://github.com/docker-library/php/issues/1074
>>>>>>> b6080d7e (cli and zts)
					continue
				fi
			fi
=======
		for variant in cli swoole zts; do
<<<<<<< HEAD
<<<<<<< HEAD
<<<<<<< HEAD
<<<<<<< HEAD
			# if [[ "$suite" = alpine* ]]; then
			# 	if [ "$variant" = 'zts' ]; then
			# 		continue
			# 	fi
			# fi
>>>>>>> 7b53e81b (adder 8,0)
=======
=======
>>>>>>> 94ac709b (Update 8.0)
			if [[ "$version" == "8.0" && !("$suite" == "bullseye" || "$suite" == "alpine3.16") ]]; then
				echo "Skipping $version $suite"
				continue
			fi
			if [[ "$version" != "8.0" &&  "$suite" == "alpine3.16" ]]; then
				echo "Skipping $version $suite"
				continue
			fi
<<<<<<< HEAD
>>>>>>> 8b7004a0 (fix 8.0 latest eol release)
=======
>>>>>>> 18f9a930 (remove 8.0 eol)
=======
>>>>>>> 94ac709b (Update 8.0)
=======
			# if [[ "$version" == "8.0" && !("$suite" == "bullseye" || "$suite" == "alpine3.16") ]]; then
			# 	echo "Skipping $version $suite"
			# 	continue
			# fi
			# if [[ "$version" != "8.0" &&  "$suite" == "alpine3.16" ]]; then
			# 	echo "Skipping $version $suite"
			# 	continue
			# fi
>>>>>>> 8d656cb0 (Remove 8.0 release EOL)
			export suite variant
			variants="$(jq <<<"$variants" -c '. + [ env.suite + "/" + env.variant ]')"
		done
	done

	echo "$version: $fullVersion"
	# sed -i '' "s/\(\"8.2-rc\"=\"[^\"]*\"\)/\"8.2-rc\"=\"$fullVersion\"/" .env.current.version
	if ! grep -q "^$version=" .env.current.version; then
		echo "$version=$fullVersion" >> .env.current.version
	else
		sed -i '' "s/\(\"$version\"=\"[^\"]*\"\)/\"$version\"=\"$fullVersion\"/" .env.current.version
	fi
	export fullVersion url ascUrl sha256
	json="$(
		jq <<<"$json" -c --argjson variants "$variants" '
			.[env.version] = {
				version: env.fullVersion,
				url: env.url,
				ascUrl: env.ascUrl,
				sha256: env.sha256,
				variants: $variants,
			}
		'
	)"

	if [ "$version" = "$rcVersion" ]; then
		json="$(jq <<<"$json" -c '
			.[env.version + "-rc"] //= null
		')"
	fi
done

jq <<<"$json" -S . >versions.json
