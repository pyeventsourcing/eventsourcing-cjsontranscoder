.EXPORT_ALL_VARIABLES:

COMPOSE_FILE ?= docker/docker-compose-local.yml
COMPOSE_PROJECT_NAME ?= eventsourcing-cjsontranscoder

POETRY_VERSION = 1.1.11
POETRY ?= poetry

DOTENV_BASE_FILE ?= .env-base
DOTENV_LOCAL_FILE ?= .env

POETRY_INSTALLER_URL ?= https://install.python-poetry.org

-include $(DOTENV_BASE_FILE)
-include $(DOTENV_LOCAL_FILE)

.PHONY: install-poetry
install-poetry:
	curl -sSL $(POETRY_INSTALLER_URL) | python3
	$(POETRY) --version

.PHONY: install-packages
install-packages:
	$(POETRY) install -vv $(opts)

.PHONY: install-pre-commit-hooks
install-pre-commit-hooks:
ifeq ($(opts),)
	$(POETRY) run pre-commit install
endif

.PHONY: uninstall-pre-commit-hooks
uninstall-pre-commit-hooks:
ifeq ($(opts),)
	$(POETRY) run pre-commit uninstall
endif

.PHONY: install
install: install-poetry install-packages

.PHONY: lock-packages
lock-packages:
	$(POETRY) lock -vv --no-update

.PHONY: update-packages
update-packages:
	$(POETRY) update -vv

.PHONY: docker-up
docker-up:
	docker-compose up -d
	docker-compose ps

.PHONY: docker-down
docker-down:
	docker-compose stop

.PHONY: docker-logs
docker-logs:
	docker-compose logs --follow

.PHONY: docker-ps
docker-ps:
	docker-compose ps

.PHONY: lint-black
lint-black:
	$(POETRY) run black --check --diff .

.PHONY: lint-flake8
lint-flake8:
	$(POETRY) run flake8

.PHONY: lint-isort
lint-isort:
	$(POETRY) run isort --check-only --diff .

.PHONY: lint-mypy
lint-mypy:
	$(POETRY) run mypy

.PHONY: lint-python
lint-python: lint-black lint-flake8 lint-isort #lint-mypy

.PHONY: lint
lint: lint-python

.PHONY: fmt-black
fmt-black:
	$(POETRY) run black .

.PHONY: fmt-isort
fmt-isort:
	$(POETRY) run isort .

.PHONY: fmt
fmt: fmt-black fmt-isort

.PHONY: test
test:
	$(POETRY) run python -m pytest -v $(opts) $(call tests,.)

.PHONY: build
build:
	$(POETRY) build -f sdist

.PHONY: publish
publish:
	$(POETRY) publish

.PHONY: build-inplace
build-inplace:
	$(POETRY) run cythonize -i eventsourcing_cjsontranscoder.pyx
	$(POETRY) run cythonize -i tests/cjson_transcodings.pyx

