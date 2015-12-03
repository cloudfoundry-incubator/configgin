#!/bin/bash

apt-get install --assume-yes rsync

set -e

if [ "$APP_VERSION" == "" ] ; then
	echo "APP_VERSION not set, aborting. Please call this from make."
	exit 1
fi

if [ "$BRANCH" == "" ] ; then
	echo "BRANCH not set, aborting. Please call this from make."
	exit 1
fi

app_name="configgin-${APP_VERSION}_${BRANCH}-linux-x86_64"
traveling_ruby="traveling-ruby-20141215-2.1.5-linux-x86_64.tar.gz"

mkdir -p ./output/${app_name}/lib/app
rsync -a --exclude output --exclude .git --exclude .gitignore  ./ ./output/${app_name}/lib/app

mkdir -p ./output/packaging

(
	cd ./output
	(
		cd ./packaging
		curl -sS -L -O --fail http://d6r77u77i8pq3.cloudfront.net/releases/${traveling_ruby}
	)
	mkdir -p ${app_name}/lib/ruby
	tar -xzf packaging/${traveling_ruby} -C ${app_name}/lib/ruby
)

cat >./output/${app_name}/configgin <<'EOL'
#!/bin/bash
set -e

# Figure out where this script is located.
SELFDIR="`dirname \"$0\"`"
SELFDIR="`cd "$SELFDIR" && pwd`"

# Tell Bundler where the Gemfile and gems are.
export BUNDLE_GEMFILE="$SELFDIR/lib/vendor/Gemfile"
unset BUNDLE_IGNORE_CONFIG

# Run the actual app using the bundled Ruby interpreter.
exec "$SELFDIR/lib/ruby/bin/ruby" -rbundler/setup "$SELFDIR/lib/app/bin/configgin" "$@"
EOL

chmod +x ./output/${app_name}/configgin

(
	cd ./output/${app_name}/lib/app
	BUNDLE_IGNORE_CONFIG=1 ../ruby/bin/bundle install --path ../vendor
	rm -rf ../vendor/*/*/cache/*
)

cp ./Gemfile ./output/${app_name}/lib/vendor
cp ./Gemfile.lock ./output/${app_name}/lib/vendor

mkdir -p ./output/${app_name}/lib/vendor/.bundle

cat > ./output/${app_name}/lib/vendor/.bundle/config <<EOL
BUNDLE_PATH: .
BUNDLE_WITHOUT: development
BUNDLE_DISABLE_SHARED_GEMS: '1'
EOL

(
	cd ./output/${app_name}
	tar -zcf ../${app_name}.tgz .
)
# vim: set ts=2:
