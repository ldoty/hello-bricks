# This file from ssh://git@stash.adconion.com:7999/all/makefiles.git
MAKEFILE_REPO := ssh://git@stash.adconion.com:7999/all/makefiles.git
MAKEFILE_NAME := Makefile.npm
MAKEFILE_VERSION := 1.20
BASE_VERSION := 0.2.0-SNAPSHOT
# For testing
MAKEFILE_BRANCH?=master
_MAKEFILE_BRANCH := $(MAKEFILE_BRANCH)

# Retrieve the artifact Name and Version
NODE?=node
NPM?=npm
NAME_:=$(shell $(NODE) -e 'console.log(require("./package.json").name)')
VERSION_:=$(shell $(NODE) -e 'console.log(require("./package.json").version)')
NAME?=$(NAME_)
VERSION?=$(VERSION_)
MASTER_BRANCH?=origin/master
XPROFILES?=

# Target environment for bricks commands
BRICKS?=vagrant

# Set DOCKER_SUDO='' if you run docker without sudo permissions
DOCKER_SUDO?=sudo

DOCKER_TIMEOUT_SEC?=1

#Set OFFLINE=true to bypass self_check when offline or there are issues with stash
OFFLINE?=false

# Constants
DOCKER?=docker
OLD_REPOSITORY?=docker-registry.adconion.com
REPOSITORY?=docker.repo.amobee.com
DOCKER_BUILD_FLAGS?=
BUILD_ARGS=--build-arg='NAME=${NAME}' --build-arg='VERSION=${VERSION}'
GIT_COMMIT?=$(shell git log -1 --format=%H)
GIT_COMMIT_LABEL?=--label git_commit_hash=${GIT_COMMIT}

#Work around to run docker command in vagrant due to incompatibility with OSX sierra
DOCKER_HACK?=false
ifeq (true, $(DOCKER_HACK))
override DOCKER=vagrant ssh -- cd $$(pwd) \&\& docker
endif

CMDLINE = "GIT_COMMIT=$(GIT_COMMIT)" "OLD_REPOSITORY=$(OLD_REPOSITORY)" "REPOSITORY=$(REPOSITORY)" "NAME=$(NAME)" "VERSION=$(VERSION)" "DOCKER_SUDO=$(DOCKER_SUDO)" "DOCKER=$(DOCKER)" "XPROFILES=$(XPROFILES)" "OFFLINE=$(OFFLINE)" "DOCKER_HACK=$(DOCKER_HACK)"

default: build test install

# ***
# TARGET: clean
#   Remove local compilation outputs and local tagged docker image
# ***
clean: self_check clean_impl clean_docker clean_children

clean_impl:
	rm -rf node_modules

clean_docker: docker_check
	@if [ -f Dockerfile ]; then \
		(set -x; \
			${DOCKER_SUDO} ${DOCKER} rmi -f \
				${NAME}:${VERSION} \
				${NAME}:latest \
				${OLD_REPOSITORY}/${NAME}:${VERSION} \
				${OLD_REPOSITORY}/${NAME}:latest \
				${REPOSITORY}/${NAME}:${VERSION} \
				${REPOSITORY}/${NAME}:latest \
				${NAME}-launcher:${VERSION} \
				${NAME}-launcher:latest \
				${REPOSITORY}/${NAME}-launcher:${VERSION} \
				${REPOSITORY}/${NAME}-launcher:latest \
		); \
		echo; \
		echo; \
		echo "Ignore above errors if docker can't find images to remove"; \
		echo; \
		echo; \
		exit 0; \
	fi

clean_children:
	@for i in $$(/bin/ls -d *); do \
	    if [ -f "$$i/Makefile" ]; then \
			(set -x; \
				make -C $$i clean $(CMDLINE) \
			) || exit 1; \
		fi \
	done

# ***
# TARGET: build
#   Compiles application (does not run tests)
# ***
build: self_check
	$(NPM) install

# ***
# TARGET: test
#   Executes application unit tests
# ***
test: self_check
	$(NPM) test

# ***
# TARGET: install
#   Installs compilation artifacts in local repository/cache
#   Builds a local docker image tagged with the specific version number
#   Tags the local docker image as latest
# ***
install: self_check install_docker install_bricks install_children

install_docker: docker_check
	@if [ -f Dockerfile ]; then \
		(set -x; \
			${DOCKER_SUDO} ${DOCKER} build ${DOCKER_BUILD_FLAGS} ${GIT_COMMIT_LABEL} -t ${NAME}:${VERSION} . || exit $$? ; \
			${DOCKER_SUDO} ${DOCKER} rmi \
				${NAME}:latest \
				${OLD_REPOSITORY}/${NAME}:${VERSION} \
				${OLD_REPOSITORY}/${NAME}:latest \
				${REPOSITORY}/${NAME}:${VERSION} \
				${REPOSITORY}/${NAME}:latest; \
				>/dev/null 2>&1; \
			${DOCKER_SUDO} ${DOCKER} tag ${NAME}:${VERSION} ${NAME}:latest && \
			${DOCKER_SUDO} ${DOCKER} tag ${NAME}:${VERSION} ${OLD_REPOSITORY}/${NAME}:${VERSION} && \
			${DOCKER_SUDO} ${DOCKER} tag ${NAME}:${VERSION} ${OLD_REPOSITORY}/${NAME}:latest && \
			${DOCKER_SUDO} ${DOCKER} tag ${NAME}:${VERSION} ${REPOSITORY}/${NAME}:${VERSION} && \
			${DOCKER_SUDO} ${DOCKER} tag ${NAME}:${VERSION} ${REPOSITORY}/${NAME}:latest; \
		); \
	fi

install_bricks: docker_check
	@if [ -d bricks ]; then \
		rm -rf .bricks-build ; \
		mkdir -p .bricks-build && \
		cp -a bricks .bricks-build && \
		${DOCKER_SUDO} ${DOCKER} run -i --rm -e "NAME=${NAME}" -e "VERSION=${VERSION}" ${REPOSITORY}/launcher-base:${BASE_VERSION} \
			export-launcher < bricks/config.yaml > .bricks-build/Dockerfile.launch && \
			${DOCKER_SUDO} ${DOCKER} build ${DOCKER_BUILD_FLAGS} ${GIT_COMMIT_LABEL} ${BUILD_ARGS} -t ${NAME}-launcher:${VERSION} -f .bricks-build/Dockerfile.launch .bricks-build && \
		${DOCKER_SUDO} ${DOCKER} rmi \
			${NAME}-launcher:latest && \
			${REPOSITORY}/${NAME}-launcher:latest && \
			${REPOSITORY}/${NAME}-launcher:${VERSION} ; \
			>/dev/null 2>&1; \
		${DOCKER_SUDO} ${DOCKER} tag ${NAME}-launcher:${VERSION} ${NAME}-launcher:latest && \
		${DOCKER_SUDO} ${DOCKER} tag ${NAME}-launcher:${VERSION} ${REPOSITORY}/${NAME}-launcher:latest && \
		${DOCKER_SUDO} ${DOCKER} tag ${NAME}-launcher:${VERSION} ${REPOSITORY}/${NAME}-launcher:${VERSION} ; \
	fi

install_children:
	@for i in $$(/bin/ls -d *); do \
	    if [ -f "$$i/Makefile" ]; then \
			(set -x; \
				make -C $$i install $(CMDLINE) \
			) || exit 1; \
		fi \
	done

# ***
# TARGET: push
#   Deploys compliation artifacts/packages to enterprise repository
#   Adds the repository identifier to the docker image and pushes to the docker registry
#   NOTE: Only Jenkins should have permission to push non-SNAPSHOT releases.
# ***
push: self_check push_docker push_bricks push_children

push_docker: master_check docker_check
	@if [ -f Dockerfile ]; then \
		(set -x; \
			${DOCKER_SUDO} ${DOCKER} push ${OLD_REPOSITORY}/${NAME}:${VERSION} && \
			${DOCKER_SUDO} ${DOCKER} push ${REPOSITORY}/${NAME}:${VERSION} \
		); \
	else \
		echo "No Dockerfile, no image to push"; \
	fi

push_bricks: master_check docker_check
	@if [ -d bricks ]; then \
		(set -x; \
			${DOCKER_SUDO} ${DOCKER} push ${REPOSITORY}/${NAME}-launcher:${VERSION} \
		); \
	fi

push_children:
	@for i in $$(/bin/ls -d *); do \
	    if [ -f "$$i/Makefile" ]; then \
			(set -x; \
				make -C $$i push $(CMDLINE) \
			) || exit 1; \
		fi \
	done

# ***
# TARGET: latest
#   Tags the specific version of the docker image in the registry as the latest version
#   NOTE: Only Jenkins should have permission to tag as latest in the repository
# ***
latest: self_check latest_docker latest_bricks latest_children

latest_docker: master_check docker_check
	@if [ -f Dockerfile ]; then \
		VERSION=${VERSION}; \
		if [ "$${VERSION%-SNAPSHOT}" = "$${VERSION}" ]; then \
			(set -x; \
				${DOCKER_SUDO} ${DOCKER} push ${OLD_REPOSITORY}/${NAME}:latest && \
				${DOCKER_SUDO} ${DOCKER} push ${REPOSITORY}/${NAME}:latest \
			); \
		else \
			echo "Not pushing snapshot version as 'latest': $${VERSION}"; \
		fi \
	else \
		echo "No Dockerfile, no image to tag"; \
	fi

latest_bricks: master_check docker_check
	@if [ -d bricks ]; then \
		VERSION=${VERSION}; \
		if [ "$${VERSION%-SNAPSHOT}" = "$${VERSION}" ]; then \
			(set -x; \
				${DOCKER_SUDO} ${DOCKER} push ${REPOSITORY}/${NAME}-launcher:latest \
			); \
		else \
			echo "Not pushing launcher snapshot version as 'latest': $${VERSION}"; \
		fi \
	else \
		echo "No bricks directory, no launcher image to tag"; \
	fi

latest_children:
	@for i in $$(/bin/ls -d *); do \
	    if [ -f "$$i/Makefile" ]; then \
			(set -x; \
				make -C $$i latest $(CMDLINE) \
			) || exit 1; \
		fi \
	done

# ***
# TARGET: tag
#   Creates a tag in the projects git repository and pushes to origin
#   NOTE: Only Jenkins should be pushing tags in git
# ***
tag: self_check master_check
	@VERSION=${VERSION}; \
	if [ "$${VERSION%-SNAPSHOT}" = "$${VERSION}" ]; then \
		(set -x; \
			git tag -a -m '' builds/${VERSION} && \
			git push origin builds/${VERSION} \
		); \
	else \
		echo "Not tagging snapshot version: $${VERSION}"; \
	fi

# ***
# TARGET: release
#   Used by Jenkins to perform releases
# ****
release: clean build test install tag push latest

# ***
# TARGET: run
#   Runs the project locally
# ***
run: self_check
	$(NPM) start

# ***
# TARGET: debug
#   Debugs the project locally
# ***
debug: self_check
	$(NPM) debug

# ***
# TARGET: bricks_start
#   Launches the application in a vagrant or lab instance with bricks
# ***
bricks_start: self_check
	bricks ${BRICKS} docker:start,${NAME},${VERSION},extra_profiles=${XPROFILES}

# ***
# TARGET: bricks_stop
#   Stops the application in a vagrant or lab instance with bricks
# ***
bricks_stop: self_check
	bricks ${BRICKS} docker:stop,${NAME},${VERSION}

# ***
# TARGET: bricks_export
#   Exports kubernetes resource definitions
# ***
bricks_export: self_check
	@if [ "$$BRICKS_MAJOR_VERSION" != "2" ]; then \
		(echo Bricks1 does not implement the 'bricks_export' target); \
	else \
		(set -x; \
			bricks vagrant app.export:${NAME},${VERSION},cluster=${BRICKS},xprofiles=${XPROFILES} | tar xf - \
		); \
	fi

# ***
# TARGET: bricks_deploy
#   Deploys application into kubernetes cluster
# ***
bricks_deploy: self_check
	@if [ "$$BRICKS_MAJOR_VERSION" != "2" ]; then \
		(echo Bricks1 does not implement the 'bricks_deploy' target); \
	else \
		(set -x; \
			bricks ${BRICKS} app.deploy:${NAME},${VERSION},xprofiles=${XPROFILES} \
		); \
	fi

info:
	@echo "$(NAME):$(VERSION)"

# ***
# TARGET: self_check
#   Checks the version of the makefile in stash to see if an update exists
#   To stop printing a message, you can issue 'touch .makefile_<new-version>'
#   in the directory where this file is located
# ***
ifeq (true, $(OFFLINE)) 
self_check:
else
self_check: check_self check_children
endif

check_self:
	@git_makefile_version=$$(git archive --remote '$(MAKEFILE_REPO)' $(_MAKEFILE_BRANCH) 2>/dev/null \
				 | tar xOf - $(MAKEFILE_NAME) 2>/dev/null \
				 | grep '^MAKEFILE_VERSION := ' 2>/dev/null \
				 | sed 's/^MAKEFILE_VERSION := \(.*\)/\1/' 2>/dev/null); \
	if [ -n "$${git_makefile_version}" -a \
	    ! -f "$(CURDIR)/.makefile_$${git_makefile_version}" ]; then \
   		if [ "$${git_makefile_version}" != "$(MAKEFILE_VERSION)" ]; then \
			echo "" ;\
			echo "" ;\
			echo "Repository $(MAKEFILE_NAME)": $${git_makefile_version} ;\
			echo "Local Makefile: $(MAKEFILE_VERSION)" ;\
			echo "Status: out-of-date"; \
			echo "Override file for this message: $(CURDIR)/.makefile_$${git_makefile_version}'"; \
			echo "" ;\
			echo "Run 'make self_update' to update Makefile to $${git_makefile_version}" ;\
			echo "" ;\
			echo "" ;\
		fi; \
	fi

check_children:
	@for i in $$(/bin/ls -d *); do \
	    if [ -f "$$i/Makefile" ]; then \
			make -C $$i self_check $(CMDLINE) || exit 1; \
		fi \
	done

# ***
# TARGET: self_update
#   Copies the latest version of the makefile in stash to the local
#   repository
# ***
self_update: update_self update_children

update_self:
	@echo "Fetching new Makefile for compare..."; \
	git archive --remote '$(MAKEFILE_REPO)' $(_MAKEFILE_BRANCH) \
		 | tar xOf - $(MAKEFILE_NAME) > Makefile.new || { rm -f Makefile.new ; exit 1; }; \
	MORE=$$(which less); \
	[ -x "$${MORE}" ] || MORE=more; \
	diff -u Makefile Makefile.new | $${MORE}; \
	echo ""; \
	printf "OK to make changes (Y/n)? "; \
	read ans; \
	if [ -z "$${ans}" -o "$${ans:0:1}" = "y" -o "$${ans:0:1}" = "Y" ]; then \
		echo "Backing up old Makefile to Makefile.bak"; \
		\mv -f Makefile Makefile.bak; \
		\mv -f Makefile.new Makefile; \
	else \
		echo "New Makefile is in Makefile.new"; \
	fi

update_children:
	@for i in $$(/bin/ls -d *); do \
	    if [ -f "$$i/Makefile" ]; then \
			(set -x; \
				make -C $$i self_update $(CMDLINE) \
			) || exit 1; \
		fi \
	done

# ***
# TARGET: master_check
#   Fails if the current branch is not the master branch and the version is
#   not a -SNAPSHOT version.  Used to prevent both tagging in git and
#   pushing non-snapshot artifacts to public repositories from develompent
#   branches.  Can be overridden by setting the MASTER_BRANCH environment
#   variable to the current branch.
# ***
master_check:
	@VERSION="${VERSION}"; \
	git_commit=$$(git rev-parse HEAD); \
	master_commit=$$(git rev-parse ${MASTER_BRANCH}); \
	if [ "$${VERSION%-SNAPSHOT}" = "$${VERSION}" -a "$${git_commit}" != "$${master_commit}" ]; then \
		echo "Cannot execute target on branch '$$(git name-rev --name-only HEAD)' for version '$${VERSION}'."; \
		exit 1; \
	fi

docker_check:
	@if [ -f Dockerfile ]; then \
		if [ -z $${DOCKER_HOST+x} ]; then \
			${DOCKER_SUDO} ${DOCKER} version &> /dev/null || { echo "Unable to connect to docker daemon" 1>&2; exit 1;} \
		else \
			RESOLVED_DOCKER_HOST=$$(echo $${DOCKER_HOST} | sed 's^tcp:^http:^'); \
			curl -fs --connect-timeout ${DOCKER_TIMEOUT_SEC} $${RESOLVED_DOCKER_HOST}/version > /dev/null \
			|| { echo "Docker timed out connecting to $${RESOLVED_DOCKER_HOST}" 1>&2; exit 1; } \
		fi \
	fi

# .PHONY is important since our target names are not real files/folders
# https://www.gnu.org/software/make/manual/html_node/Phony-Targets.html
.PHONY: clean clean_children clean_impl clean_docker docker_check build test install install_children install_impl install_docker install_bricks \
	push push_children push_impl push_docker push_bricks latest latest_children latest_impl latest_docker latest_bricks \
	tag tag_impl tag_git run debug bricks_stop bricks_start bricks_deploy bricks_export release self_check self_update update_children master_check info itest itest_run itest_deps \
	itest_bootstrap itest_run_children itest_deps_children

# vim:ft=make: