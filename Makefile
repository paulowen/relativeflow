.PHONY: all

all: release

release:
	hugo
	aws s3 sync --acl "public-read" --storage-class "REDUCED_REDUNDANCY" --sse "AES256" --size-only public/ s3://www.relativeflow.com --exclude '.DS_Store'

clean:
	$(RM) -r public
