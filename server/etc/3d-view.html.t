<!DOCTYPE html>
<html>
   <head>
      <meta charset="utf-8">
      <title>Phoria - Dev test page 0</title>
      <script src="/beslim.ai/phoria.js/gl-matrix.js"></script>
      <script src="/beslim.ai/phoria.js/phoria-util.js"></script>
      <script src="/beslim.ai/phoria.js/phoria-entity.js"></script>
      <script src="/beslim.ai/phoria.js/phoria-scene.js"></script>
      <script src="/beslim.ai/phoria.js/phoria-renderer.js"></script>
      <script src='/beslim.ai/phoria.js/dat.gui.min.js'></script>      
      <script>

var scene = null;
var renderer = null;

window.addEventListener('load', init, false);
window.addEventListener("resize", refresh);

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

function init()
{
   // get the canvas DOM element and the 2D drawing context
   var canvas = document.getElementById('canvas');
 
   document.body.style.margin = "0px";
   document.body.style.overflow = "hidden";
 
   canvas.width = window.innerWidth;
   canvas.height = window.innerHeight;
 
   // create the scene and setup camera, perspective and viewport
   scene = new Phoria.Scene();

   scene.perspective.aspect = canvas.width / canvas.height;

   // We can't set different xFov and yFov, so set sane one instead
   scene.perspective.fov = 75.0

   scene.viewport.width = canvas.width;
   scene.viewport.height = canvas.height;
   
   renderer = new Phoria.CanvasRenderer(canvas);
   
   var maskPoints = ##maskPoints##;

   var maskEdges = ##maskEdges##;

   var mask = Phoria.Entity.create({
      points: maskPoints,
      edges: maskEdges,
      polygons: [],
      style: {
         drawmode: "wireframe",
         shademode: "plain",
         linewidth: 2.0,
         objectsortmode: "back",
         color: [0, 0, 255]
      }
   });

   scene.graph.push(mask);

   scene.camera.position.x = ##cameraX##;
   scene.camera.position.y = ##cameraY##;
   scene.camera.position.z = ##cameraZ##;

   scene.camera.up.x = ##cameraUpX##;
   scene.camera.up.y = ##cameraUpY##;
   scene.camera.up.z = ##cameraUpZ##;

   scene.camera.lookat.x = ##lookAtX##;
   scene.camera.lookat.y = ##lookAtY##;
   scene.camera.lookat.z = ##lookAtZ##;



   var heading = 0.0;
   var lookAt = vec3.fromValues(0,-5,15);

   /**
    * @param forward {vec3}   Forward movement offset
    * @param heading {float}  Heading in Phoria.RADIANS
    * @param lookAt {vec3}    Lookat projection offset from updated position
    */
   var fnPositionLookAt = function positionLookAt(forward, heading, lookAt) {
      // recalculate camera position based on heading and forward offset
      var pos = vec3.fromValues(
         scene.camera.position.x,
         scene.camera.position.y,
         scene.camera.position.z);
      var ca = Math.cos(heading), sa = Math.sin(heading);
      var rx = forward[0]*ca - forward[2]*sa,
          rz = forward[0]*sa + forward[2]*ca;
      forward[0] = rx;
      forward[2] = rz;
      vec3.add(pos, pos, forward);
      scene.camera.position.x = pos[0];
      scene.camera.position.y = pos[1];
      scene.camera.position.z = pos[2];

      // calcuate rotation based on heading - apply to lookAt offset vector
      rx = lookAt[0]*ca - lookAt[2]*sa,
      rz = lookAt[0]*sa + lookAt[2]*ca;
      vec3.add(pos, pos, vec3.fromValues(rx, lookAt[1], rz));

      // set new camera look at
      scene.camera.lookat.x = pos[0];
      scene.camera.lookat.y = pos[1];
      scene.camera.lookat.z = pos[2];

      scene.modelView();
      renderer.render(scene);
   }
   
   // key binding
   document.addEventListener('keydown', function(e) {
      switch (e.keyCode)
      {
         case 87: // W
            // move forward along current heading
            fnPositionLookAt(vec3.fromValues(0,0,1), heading, lookAt);
            break;
         case 83: // S
            // move back along current heading
            fnPositionLookAt(vec3.fromValues(0,0,-1), heading, lookAt);
            break;
         case 65: // A
            // strafe left from current heading
            fnPositionLookAt(vec3.fromValues(-1,0,0), heading, lookAt);
            break;
         case 68: // D
            // strafe right from current heading
            fnPositionLookAt(vec3.fromValues(1,0,0), heading, lookAt);
            break;
         case 37: // LEFT
            // turn left
            heading += Phoria.RADIANS*4;
            // recalculate lookAt
            // given current camera position, project a lookAt vector along current heading for N units
            fnPositionLookAt(vec3.fromValues(0,0,0), heading, lookAt);
            break;
         case 39: // RIGHT
            // turn right
            heading -= Phoria.RADIANS*4;
            // recalculate lookAt
            // given current camera position, project a lookAt vector along current heading for N units
            fnPositionLookAt(vec3.fromValues(0,0,0), heading, lookAt);
            break;
         case 38: // UP
            lookAt[1]++;
            fnPositionLookAt(vec3.fromValues(0,0,0), heading, lookAt);
            break;
         case 40: // DOWN
            lookAt[1]--;
            fnPositionLookAt(vec3.fromValues(0,0,0), heading, lookAt);
            break;
      }
   }, false);

   /*
   KEY:
   {
      SHIFT:16, CTRL:17, ESC:27, RIGHT:39, UP:38, LEFT:37, DOWN:40, SPACE:32,
      A:65, E:69, G:71, L:76, P:80, R:82, S:83, Z:90
   },
   */

   refresh();
}
      </script>
   </head>
   
   <body style="background-color: #bfbfbf">
      <canvas id="canvas" style="background-color: #eee; position: absolute;"></canvas>
   </body>
</html>
