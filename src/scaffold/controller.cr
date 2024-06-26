module Scaffold
  abstract class Controller
    include HTTP::Handler

    macro inherited
      private ROUTES = {} of {String, String} => {String, Bool}

      macro method_added(method)
        \{% if anno = method.annotation(::SC::Get) || method.annotation(::SC::Post) %}
          \{% anno.raise "no route argument specified in annotation" if anno.args.empty? %}
          \{% route = anno.args[0] %}
          \{% unless route.class_name == "StringLiteral" %}
            \{% anno.raise "route argument must be a string literal" %}
          \{% end %}
          \{% verb = anno.name.names.last.upcase.stringify %}
          \{% if ROUTES[{verb, route}] %}
            \{% anno.raise "a route already exists with this method" %}
          \{% end %}
          \{% ROUTES[{verb, route}] = {method.name, method.args.empty?} %}
        \{% end %}
      end

      macro finished
        def call(context : ::HTTP::Server::Context) : ::Nil
          req, res = context.request, context.response
          case {req.method, parse_route(req.path)}
          \{% for route, method in ROUTES %}
          when \{{ route }}
            \{% if method[1] %}
              transform res, \{{ method[0] }}
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
        \{% debug %}
      end
    end

    protected def parse_route(route : String) : String | Regex
      route # TODO
    end

    def transform(res : Response, value : String) : Nil
      res << value
    end

    def transform(res : Response, value : Response) : Nil
    end

    def transform(res : Response, value : Exception) : Nil
      res.status = :internal_server_error
      res << "An unexpected exception occurred: " << value << '\n'
    end

    def transform(res : Response, value : T) : NoReturn forall T
      {% T.raise "no transformer method defined for type #{T}" %}
    end
  end
end
