require "http/server"

require "./scaffold/*"

module Scaffold
  VERSION = "0.1.0"

  alias Response = HTTP::Server::Response
end

alias SC = Scaffold
