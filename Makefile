.PHONY: all

all: release

release:
	hugo
	s3cmd sync --delete-removed -P public/ s3://www.relativeflow.com/ ; \
        s3cmd put --acl-public keybase.txt s3://www.relativeflow.com/

clean:
	$(RM) -r public
