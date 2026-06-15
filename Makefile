.PHONY: test icon app dmg install status clean

test:
	swift run UsageCoreTests

icon:
	./scripts/build-icon.sh

app:
	./scripts/build-app.sh

dmg:
	./scripts/make-dmg.sh

# Installs to /Applications and (re)launches the app.
install: app
	-pkill -x ClaudeUsageTracker 2>/dev/null || true
	rm -rf /Applications/ClaudeUsageTracker.app
	cp -R build/ClaudeUsageTracker.app /Applications/
	open /Applications/ClaudeUsageTracker.app

# Prints what the menu bar would show, without launching the GUI.
status:
	swift run ClaudeUsageTracker --status

clean:
	rm -rf .build build
