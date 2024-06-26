module Scaffold
  abstract class Controller
    include HTTP::Handler

    macro inherited
      private ROUTES = {} of {String, String | Regex} => {String, Int32}

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
            \{% if count > 2 %}
              \{% method.raise "route methods can only accept a request and response as arguments" %}
            \{% end %}
            \{% if count == 1 && method.args[0].restriction %}
              \{% type = method.args[0].restriction.resolve %}
              \{% if type <= ::HTTP::Request %}
                \{% count = -1 %}
              \{% elsif type <= ::HTTP::Server::Response %}
                \{% count = -2 %}
              \{% else %}
                \{% method.raise "route methods can only accept a request and response as arguments" %}
              \{% end %}
            \{% end %}
            \{% ROUTES[{verb, route}] = {method.name, count} %}
          \{% end %}
        {% end %}
      end

      macro finished
        def call(context : ::HTTP::Server::Context) : ::Nil
          req, res = context.request, context.response
          case {req.method, req.path}
          \{% for route, method in ROUTES %}
          when \{{ route }}
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
      res << "An unexpected exception occurred: " << value << '\n'
    end

    def transform(res : Response, value : T) : NoReturn forall T
      {% T.raise "no transform method defined for type #{T}" %}
    end
  end
end
