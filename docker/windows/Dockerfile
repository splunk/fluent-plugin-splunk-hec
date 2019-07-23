FROM mcr.microsoft.com/windows/servercore:ltsc2019

LABEL maintainer="Splunk Inc. <DataEdge@splunk.com>"

# skip runtime bundler installation
ENV FLUENTD_DISABLE_BUNDLER_INJECTION 1
COPY *.gem /tmp/

RUN powershell -Command \
  Set-ExecutionPolicy Bypass -Scope Process -Force; \
  iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))

RUN choco install -y ruby --version 2.4.2.2 --params "'/InstallDir:C:\'" \
  && choco install -y msys2 --params "'/NoPath /NoUpdate /InstallDir:C:\ruby24\msys64'" \
  && refreshenv \
  && ridk install 2 3

RUN echo gem: --no-document >> C:\ProgramData\gemrc \
  && gem install -N fluentd -v "1.4.0" \
  && gem install -N fluent-plugin-windows-eventlog -v "0.3.0" \
  && gem install -N fluent-plugin-concat -v "2.2.2" \
  && gem install -N fluent-plugin-prometheus -v "1.3.0" \
  && gem install -N oj -v "3.5.1" \
  && gem install -N /tmp/*.gem \
  && gem sources --clear-all \
  && mkdir C:\fluentd\etc

# plugin hardfails when using net-http-persistent 3.0.1 on windows
# https://github.com/drbrain/net-http-persistent/issues/79#issuecomment-347541046
# make an inline replacement to net-http-persistent to resolve
RUN powershell -Command " \
$file = 'C:\ruby24\lib\ruby\gems\2.4.0\gems\net-http-persistent-3.0.1\lib\net\http\persistent.rb'; \
$content = (Get-Content -Path $file).Replace(\"  DEFAULT_POOL_SIZE = Process.getrlimit(Process::RLIMIT_NOFILE).first / 4\", \"  if Gem.win_platform? then`n    DEFAULT_POOL_SIZE = 256`n  else`n    DEFAULT_POOL_SIZE = Process.getrlimit(Process::RLIMIT_NOFILE).first / 4`n  end\"); \
Set-Content -Path $file $content;"

# Remove gem cache
RUN powershell -Command del C:\ruby24\lib\ruby\gems\2.4.0\cache\*.gem;

ENTRYPOINT ["cmd", "/k", "fluentd"]
CMD ["-h"]
