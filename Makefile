.PHONY: all

all: release

release:
	hugo
	cp keybase.txt public/keybase.txt
	s3cmd sync --delete-removed -P public/ s3://www.relativeflow.com/ ; \

clean:
	$(RM) -r public
