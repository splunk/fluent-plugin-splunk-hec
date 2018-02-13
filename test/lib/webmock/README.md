There are two reasons why we stub out all these webmock adapter:
* Requiring 'http' (by the http_rb_adapter) will trigger a circle require warning (http/client <-> http/connection)
* We only need mocking the standard library `net/http`, and we don't want to load a bunch of not used libraries.
