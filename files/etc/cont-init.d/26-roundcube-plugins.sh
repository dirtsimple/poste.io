#!/usr/bin/env bash

set -e

PLUGIN_LIST=/data/roundcube/installed-plugins
PLUGINS_DIR=/data/roundcube-plugins

[[ -f "$PLUGIN_LIST" ]] || touch "$PLUGIN_LIST"  # plugin list must exist
[[ -d "$PLUGINS_DIR" ]] || exit 0                # but it can be empty if no plugins

cd /opt/www/webmail

log() { echo -e "\t\t\033[1;33m* $*\033[0m"; }

# Remove any plugin symlinks left over since last container rebuild
for plugin in plugins/*; do [[ ! -L "$plugin" ]] || rm "$plugin"; done

# Link and possibly-install plugins
for plugin_path in "$PLUGINS_DIR"/*; do
	[[ -d $plugin_path ]] || continue  # not a plugin

	plugin=${plugin_path##*/}

	# Remove any existing plugin of this name that's not a symlink
	if [[ -d plugins/"$plugin" && ! -L plugins/"$plugin" ]]; then
		# We must overwrite existing plugin dir, if found
		log "Removing pre-installed version of $plugin plugin"
		rm -rf plugins/$plugin
	fi

	# Symlink plugin to the plugins dir
	log "Mounting plugin $plugin"
	ln -sfn "$plugin_path" plugins/"$plugin"

	if ! grep -q "^$plugin\$" "$PLUGIN_LIST"; then
		log "Installing new roundcube plugin $plugin"

		# Not in installed plugin list; check for SQL
		sqldir=$(
			php -r 'echo(
				@json_decode(
					file_get_contents("plugins/'"$plugin"'/composer.json")
				)->extra->roundcube->{"sql-dir"}
			);'
		)
		if [[ $sqldir ]]; then
			# Got SQL
			log "Running SQL for $plugin"
			vendor/bin/rcubeinitdb.sh --package="$plugin" --dir="$plugin_path/$sqldir" || true  # ignore errors
		fi

		# Record installation complete
		echo "$plugin" >>"$PLUGIN_LIST"
	fi
done
