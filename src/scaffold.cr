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
  annotation All; end

  annotation NotFound; end
  annotation NotAllowed; end
  annotation Upgrade; end

  alias Response = HTTP::Server::Response

  abstract class Controller
    include HTTP::Handler

    macro inherited
      private SCROUTES = {} of String => Hash
      private SCHANDLE = {} of Symbol => {String, Int32}

      macro method_added(method)
        \{% count = method.args.size %}
        {% for name in %i[Get Post Patch Put Delete Head Options] %}
          \{% if anno = method.annotation(::SC::{{ name.id }}) %}
            \{% anno.raise "no route argument specified in annotation" if anno.args.empty? %}
            \{% route = anno.args[0] %}
            \{% unless route.class_name == "StringLiteral" || route.class_name == "RegexLiteral" %}
              \{% anno.raise "route argument must be a string literal or regex literal" %}
            \{% end %}
            \{% verb = anno.name.names.last.upcase.stringify %}
            \{% if SCROUTES[route] && SCROUTES[route][verb] %}
              \{% anno.raise "a route already exists with this method" %}
            \{% end %}
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
            \{% unless SCROUTES[route] %}
              \{% SCROUTES[route] = {} of String => {String, Int32, Bool} %}
            \{% end %}
            \{% SCROUTES[route][verb] = {method.name, count, upgrade} %}
          \{% end %}
        {% end %}
        {% for name in %i[NotFound NotAllowed] %}
          \{% if anno = method.annotation(::SC::{{ name.id }}) %}
            \{% anno.raise "annotation {{ name.id }} takes no arguments" unless anno.args.empty? %}
            \{% if count > 2 %}
              \{% method.raise "wrong number of arguments for handler method (given #{count}, expected 0..2)" %}
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
            \{% SCHANDLE[{{ name }}] = {method.name, count} %}
          \{% end %}
        {% end %}
      end

      macro finished
        def call(context : ::HTTP::Server::Context) : ::Nil
          case context.request.path
          \{% for route, method in SCROUTES %}
          when \{{ route }}
            case context.request.method
            \{% for verb, info in method %}
            when \{{ verb }}
              \{% if info[2] %}
                handler = ::HTTP::WebSocketHandler.new &->\{{ info[0] }}(::HTTP::WebSocket, ::HTTP::Server::Context)
                handler.call context
              \{% else %}
                \{% if info[1] == 0 %}
                  transform context.response, \{{ info[0] }}
                \{% elsif info[1] == -1 || info[1] == 1 %}
                  transform context.response, \{{ info[0] }}(context.request)
                \{% elsif info[1] == -2 %}
                  transform context.response, \{{ info[0] }}(context.response)
                \{% else %}
                  transform context.response, \{{ info[0] }}(context.request, context.response)
                \{% end %}
              \{% end %}
            \{% end %}
            else
              \{% if info = SCHANDLE[:NotAllowed] %}
                \{% if info[1] == 0 %}
                  transform context.response, \{{ info[0] }}
                \{% elsif info[1] == -1 || info[1] == 1 %}
                  transform context.response, \{{ info[0] }}(context.request)
                \{% elsif info[1] == -2 %}
                  transform context.response, \{{ info[0] }}(context.response)
                \{% else %}
                  transform context.response, \{{ info[0] }}(context.request, context.response)
                \{% end %}
              \{% else %}
                context.response.tap do |res|
                  res.status = :method_not_allowed
                  res.headers["Allow"] = \{{ method.keys.join "," }}
                end
              \{% end %}
            end
          \{% end %}
          else
            \{% if info = SCHANDLE[:NotFound] %}
              \{% if info[1] == 0 %}
                transform context.response, \{{ info[0] }}
              \{% elsif info[1] == -1 || info[1] == 1 %}
                transform context.response, \{{ info[0] }}(context.request)
              \{% elsif info[1] == -2 %}
                transform context.response, \{{ info[0] }}(context.response)
              \{% else %}
                transform context.response, \{{ info[0] }}(context.request, context.response)
              \{% end %}
            \{% else %}
              context.response.status = :not_found
            \{% end %}
          end
        rescue ex
          transform context.response, ex
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
