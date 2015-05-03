MAIN_REPO=../ocaml-mdns
DOC_DIR=$(MAIN_REPO)/doc
RFC_NOTES=$(DOC_DIR)/rfc_notes.py

all: rfc6762_notes.html rfc_notes.js rfc_notes.css
.PHONY: all

%.html: $(DOC_DIR)/%.xml $(RFC_NOTES)
	$(RFC_NOTES) $< --html $@
	git add $@

%.js: $(DOC_DIR)/%.js
	cp $< $@
	git add $@

%.css: $(DOC_DIR)/%.css
	cp $< $@
	git add $@

