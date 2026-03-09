.PHONY: lint typecheck check install dev-install

lint:
	ruff format src/ && ruff check --fix src/

typecheck:
	pyright src/

check: lint typecheck

install:
	pip install .

dev-install:
	pip install -e .
