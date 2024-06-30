require "http/server"
require "http/web_socket"

module Scaffold
  VERSION = "0.1.0"

  annotation Get; end
  annotation Post; end
  annotation Patch; end
  annotation Put; end
  annotation Delete; end
  annotation Head; end
  annotation Options; end
  annotation Upgrade; end

  alias Response = HTTP::Server::Response

  abstract class Controller
    include HTTP::Handler

    macro inherited
      private ROUTES = {} of {String, String | Regex} => {String, Int32, Bool}

      macro method_added(method)
        {% for name in %i[Get Post Patch Put Delete Head Options] %}
          \{% if anno = method.annotation(::SC::{{ name.id }}) %}
            \{% anno.raise "no route argument specified in annotation" if anno.args.empty? %}
            \{% route = anno.args[0] %}
            \{% unless route.class_name == "StringLiteral" || route.class_name == "RegexLiteral" %}
              \{% anno.raise "route argument must be a string literal or regex literal" %}
            \{% end %}
            \{% verb = anno.name.names.last.upcase.stringify %}
            \{% if ROUTES[{verb, route}] %}
              \{% anno.raise "a route already exists with this method" %}
            \{% end %}
            \{% count = method.args.size %}
            \{% upgrade = false %}
            \{% if anno = method.annotation(::SC::Upgrade) %}
              \{% if anno.args.size == 0 || anno.args.size > 1 %}
                \{% anno.raise "expected one argument for Upgrade annotation" %}
              \{% elsif anno.args[0] != :websocket %}
                \{% anno.raise "only 'websocket' is currently supported for Upgrade annotation" %}
              \{% end %}
              \{% unless count == 2 %}
                \{% method.raise "websocket route methods can only accept a websocket and context as arguments" %}
              \{% end %}
              \{% if method.args[0].restriction %}
                \{% type = method.args[0].restriction.resolve %}
                \{% unless type <= ::HTTP::WebSocket %}
                  \{% type.raise "expected argument #1 to be HTTP::WebSocket, not #{type}" %}
                \{% end %}
              \{% end %}
              \{% if method.args[1].restriction %}
                \{% type = method.args[1].restriction.resolve %}
                \{% unless type <= ::HTTP::Server::Context %}
                  \{% type.raise "expected argument #2 to be HTTP::Server::Context, not #{type}" %}
                \{% end %}
              \{% end %}
              \{% upgrade = true %}
            \{% else %}
              \{% if count > 2 %}
                \{% method.raise "wrong number of arguments for route method (given #{count}, expected 0..2)" %}
              \{% end %}
              \{% if count == 1 && method.args[0].restriction %}
                \{% type = method.args[0].restriction.resolve %}
                \{% if type <= ::HTTP::Request %}
                  \{% count = -1 %}
                \{% elsif type <= ::HTTP::Server::Response %}
                  \{% count = -2 %}
                \{% else %}
                  \{% method.raise "expected argument #1 to be HTTP::Request or HTTP::Server::Response, not #{type}" %}
                \{% end %}
              \{% end %}
            \{% end %}
            \{% ROUTES[{verb, route}] = {method.name, count, upgrade} %}
          \{% end %}
        {% end %}
      end

      macro finished
        def call(context : ::HTTP::Server::Context) : ::Nil
          req, res = context.request, context.response
          case {req.method, req.path}
          \{% for route, method in ROUTES %}
          when \{{ route }}
            \{% if method[2] %}
              handler = ::HTTP::WebSocketHandler.new &->\{{ method[0] }}(::HTTP::WebSocket, ::HTTP::Server::Context)
              handler.call context
            \{% else %}
              \{% if method[1] == 0 %}
                transform res, \{{ method[0] }}
              \{% elsif method[1] == -1 || method[1] == 1 %}
                transform res, \{{ method[0] }}(req)
              \{% elsif method[1] == -2 %}
                transform res, \{{ method[0] }}(res)
              \{% else %}
                transform res, \{{ method[0] }}(req, res)
              \{% end %}
            \{% end %}
          \{% end %}
          else
            raise "route not found"
          end
        rescue ex
          transform res.not_nil!, ex
        end
      end
    end

    def transform(res : Response, value : String) : Nil
      res << value
    end

    def transform(res : Response, value : Response?) : Nil
    end

    def transform(res : Response, value : Exception) : Nil
      res.status = :internal_server_error
      res << "An unexpected exception occurred:\n"
      value.inspect_with_backtrace res
    end

    def transform(res : Response, value : T) : NoReturn forall T
      {% T.raise "no transform method defined for type #{T}" %}
    end
  end
end

alias SC = Scaffold
