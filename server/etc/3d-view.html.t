<!DOCTYPE html>
<html>
    <head>
        <meta charset="utf-8">
        <title>##sessionId##-##attempt##</title>
        <script src="/beslim.ai/phoria.js/gl-matrix.js"></script>
        <script src="/beslim.ai/phoria.js/phoria-util.js"></script>
        <script src="/beslim.ai/phoria.js/phoria-entity.js"></script>
        <script src="/beslim.ai/phoria.js/phoria-scene.js"></script>
        <script src="/beslim.ai/phoria.js/phoria-renderer.js"></script>
        <script src='/beslim.ai/phoria.js/dat.gui.min.js'></script>
        <script>
            function refresh() {
                var canvas = document.getElementById('canvas');

                var viewportWidth = ##viewportWidth##;
                var viewportHeight = ##viewportHeight##;

                var width = window.innerHeight * (viewportWidth / viewportHeight);
                if (window.innerHeight * viewportWidth <= window.innerWidth * viewportHeight) {
                    width = window.innerHeight * (viewportWidth / viewportHeight);
                    height = window.innerHeight;
                } else {
                    width = window.innerWidth;
                    height = window.innerWidth * (viewportHeight / viewportWidth);
                }

                canvas.width = width;
                canvas.height = height;
                canvas.style.left = ((window.innerWidth - width) / 2) + "px";
                canvas.style.top = ((window.innerHeight - height) / 2) + "px";

                scene.perspective.aspect = width / height;

                scene.viewport.width = width;
                scene.viewport.height = height;

                scene.modelView();
                renderer.render(scene);
            }

            function crossProduct(a, b) {
                var r = {};

                r.x = a.y * b.z - a.z * b.y;
                r.y = a.z * b.x - a.x * b.z;
                r.z = a.x * b.y - a.y * b.x;

                return r;
            }

            function dotProduct(a, b) {
                return a.x * b.x + a.y * b.y + a.z * b.z;
            }

            function rotate(v, k, theta) {
               var r = {};

               var c = crossProduct(k, v);
               var d = dotProduct(k, v);

               var cos = Math.cos(theta);

               r.x = v.x * cos + c.x * Math.sin(theta) + k.x * d * (1.0 - cos);
               r.y = v.y * cos + c.y * Math.sin(theta) + k.y * d * (1.0 - cos);
               r.z = v.z * cos + c.z * Math.sin(theta) + k.z * d * (1.0 - cos);

               return r;
            }

            function normalize(v) {
               var d = Math.sqrt(v.x ** 2 + v.y ** 2 + v.z ** 2);

               return {x: v.x / d, y: v.y / d, z: v.z / d};
            }

            function neg(a) {
               return {x: -a.x, y: -a.y, z: -a.z};
            }

            function add(a, b) {
               return {x: a.x + b.x, y: a.y + b.y, z: a.z + b.z};
            }

            function sub(a, b) {
                return add(a, neg(b));
            }

            function mul(v, a) {
                return {x: v.x * a, y: v.y * a, z: v.z * a};
            }

            function update(t, s) {
                t.x = s.x;
                t.y = s.y;
                t.z = s.z;

                return t;
            }

            function calculateDirections() {
                var f = normalize(sub(scene.camera.lookat, scene.camera.position));

                directions.forward = f;
                directions.back = neg(f);

                var up = normalize(scene.camera.up);

                var r = crossProduct(up, f);

                directions.right = r;
                directions.left = neg(r);

                var u = crossProduct(f, r)

                directions.up = u;
                directions.down = neg(u);
            }

            function applyStyle(o, s) {
                o.style.drawmode = s.drawmode;
                o.style.shademode = s.shademode;
                o.style.opacity = s.opacity;
            }

            function control(e) {
                var lv = sub(scene.camera.lookat, scene.camera.position);
                var pd = {x: 0.0, y: 0.0, z: 0.0};

                var u = update({}, scene.camera.up);

                calculateDirections();

                switch (e.keyCode)
                {
                    case 87: // W
                        pd = mul(directions.forward, step);

                        break;

                    case 83: // S
                        pd = mul(directions.back, step);

                        break;
                    case 65: // A
                        pd = mul(directions.left, step);

                        break;
                    case 68: // D
                        pd = mul(directions.right, step);

                        break;
                  case 82: // R
                        pd = mul(directions.up, step);

                        break;
                  case 70: // F
                        pd = mul(directions.down, step);

                        break;
                    case 73: // I
                        u = rotate(scene.camera.up, directions.left, angle);
                        lv = rotate(lv, directions.left, angle);

                        break;

                    case 75: // K
                        u = rotate(scene.camera.up, directions.left, -angle);
                        lv = rotate(lv, directions.left, -angle);

                        break;

                  case 76: // L
                        u = rotate(scene.camera.up, directions.up, angle);
                        lv = rotate(lv, directions.up, angle);

                        break;

                    case 74: // J
                        u = rotate(scene.camera.up, directions.up, -angle);
                        lv = rotate(lv, directions.up, -angle);

                        break;

                    case 77: // M
                        u = rotate(scene.camera.up, directions.back, angle);

                        break;

                    case 78: // N
                        u = rotate(scene.camera.up, directions.back, -angle);

                        break;

                    case 89: //Y
                        maskStyle = (maskStyle + 1) % 3;
                        applyStyle(mask, styles[maskStyle]);

                        break;

                    case 72: //H
                        worldStyle = (worldStyle + 1) % 3;
                        applyStyle(world, styles[worldStyle]);

                        break;
                }

                update(scene.camera.position, add(scene.camera.position, pd));
                update(scene.camera.lookat, add(scene.camera.position, lv));
                update(scene.camera.up, u);

                scene.modelView();
                renderer.render(scene);
            }

            function init() {
                var canvas = document.getElementById('canvas');

                document.body.style.margin = "0px";
                document.body.style.overflow = "hidden";

                canvas.width = window.innerWidth;
                canvas.height = window.innerHeight;

                scene = new Phoria.Scene();

                scene.perspective.aspect = canvas.width / canvas.height;

                scene.perspective.fov = ##cameraFov##;

                scene.viewport.width = canvas.width;
                scene.viewport.height = canvas.height;

                renderer = new Phoria.CanvasRenderer(canvas);

                var worldPoints = ##worldPoints##;
                var worldEdges = ##worldEdges##;
                var worldPolygons = ##worldPolygons##;

                world = Phoria.Entity.create({
                    points: worldPoints,
                    edges: worldEdges,
                    polygons: worldPolygons,
                    style: {
                       linewidth: 2.0,
                       objectsortmode: "back",
                       fillmode: "fill",
                       doublesided: true,
                       color: [0, 255, 0]
                    }
                });

                scene.graph.push(world);

                var maskPoints = ##maskPoints##;
                var maskEdges = ##maskEdges##;
                var maskPolygons = ##maskPolygons##;

                mask = Phoria.Entity.create({
                    points: maskPoints,
                    edges: maskEdges,
                    polygons: maskPolygons,
                    style: {
                       linewidth: 2.0,
                       objectsortmode: "back",
                       fillmode: "fill",
                       doublesided: true,
                       color: [0, 0, 255]
                    }
                });

                scene.graph.push(mask);

                scene.graph.push(new Phoria.DistantLight());

                scene.camera.position.x = ##cameraX##;
                scene.camera.position.y = ##cameraY##;
                scene.camera.position.z = ##cameraZ##;

                scene.camera.up.x = ##cameraUpX##;
                scene.camera.up.y = ##cameraUpY##;
                scene.camera.up.z = ##cameraUpZ##;

                scene.camera.lookat.x = ##lookAtX##;
                scene.camera.lookat.y = ##lookAtY##;
                scene.camera.lookat.z = ##lookAtZ##;

                document.addEventListener('keydown', control, false);

                applyStyle(mask, styles[maskStyle]);
                applyStyle(world, styles[worldStyle]);

                refresh();
            }

            var scene = null;
            var renderer = null;

            var mask = null;
            var world = null;

            var styles = [
               {
                   drawmode: "wireframe",
                   shademode: "plain",
                   opacity: 1
               },
               {
                   drawmode: "solid",
                   shademode: "lightsource",
                   opacity: 1
               },
               {
                   drawmode: "point",
                   shademode: "plain",
                   opacity: 0
               },
            ];

            window.addEventListener('load', init, false);
            window.addEventListener('resize', refresh);

            var step = 0.1;
            var angle = Math.PI * 5.0 / 180.0;

            var maskStyle = 0;
            var worldStyle = 0;

            var directions = {};
        </script>
    </head>

    <body style="background-color: #bfbfbf">
        <canvas id="canvas" style="background-color: #eee; position: absolute;"></canvas>
    </body>
</html>
