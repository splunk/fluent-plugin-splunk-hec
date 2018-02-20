SHELL=/bin/bash

# this is supposed to be used as travis build script
.PHONY: test
test:
	@for n in 3 4 5; do \
	   docker run -it --rm -v $$(pwd):/app -w /app ruby:2.$$n-alpine /app/run_ci.sh; \
	   err=$$?; \
	   if [[ $$err -ne 0 ]]; then exit $$err; fi \
	 done
