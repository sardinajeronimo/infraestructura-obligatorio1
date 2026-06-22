-- Space Invaders - Parte 3 ADA - Obligatorio Marzo 2026
--
-- Controles: A = izquierda, D = derecha, W = disparar, Q = salir
--
-- Conceptos Ada:
--   task type Nave     : cada nave es una tarea, entry Impacto es el rendezvous
--   task type Bala     : cada bala es una tarea
--   task Coordinadora  : mueve el bloque de naves
--   task Canon         : lee teclado
--   protected Juego    : estado compartido (canon, fin, posiciones de naves)

with Ada.Text_IO;   use Ada.Text_IO;
with Ada.Real_Time; use Ada.Real_Time;
with Interfaces.C;  use Interfaces.C;
with Interfaces;    use Interfaces;

procedure Main is

   -- ============================================================
   -- CONSTANTES
   -- ============================================================
   ANCHO        : constant := 80;
   ALTO         : constant := 24;
   NAVES_X_FILA : constant := 6;
   TOTAL_NAVES  : constant := NAVES_X_FILA * 2;
   FILA_NAVES_1 : constant := 3;   -- fila superior del primer conjunto
   FILA_NAVES_2 : constant := 6;   -- fila superior del segundo conjunto
   FILA_CANON   : constant := ALTO - 1;
   SEPARACION   : constant := 12;  -- columnas entre naves

   -- ============================================================
   -- PANTALLA (secuencias ANSI)
   -- ============================================================
   ESC : constant String := ASCII.ESC & "[";

   procedure Limpiar_Pantalla is
   begin
      Put (ESC & "2J" & ESC & "H");
   end Limpiar_Pantalla;

   -- ============================================================
   -- PANTALLA PROTEGIDA
   --
   -- Todas las tasks (naves, balas, canon) escriben aca. Al ser un
   -- protected object, solo una task escribe a la vez, evitando que
   -- se intercalen las secuencias "posicionar + escribir" y queden
   -- caracteres mal dibujados o sin borrar.
   -- ============================================================
   protected Pantalla is
      procedure Poner (Fila, Columna : Integer; Car : Character);
      procedure Limpiar (Fila, Columna : Integer);
   end Pantalla;

   protected body Pantalla is
      procedure Poner (Fila, Columna : Integer; Car : Character) is
         F : constant String := Integer'Image (Fila);
         C : constant String := Integer'Image (Columna);
      begin
         Put (ESC & F (2 .. F'Last) & ";" & C (2 .. C'Last) & "H");
         Put (Car);
         Ada.Text_IO.Flush;
      end Poner;

      procedure Limpiar (Fila, Columna : Integer) is
      begin
         Poner (Fila, Columna, ' ');
      end Limpiar;
   end Pantalla;

   -- Atajos para escribir mas corto en el resto del codigo
   procedure Dibujar (Fila, Columna : Integer; Car : Character) is
   begin
      Pantalla.Poner (Fila, Columna, Car);
   end Dibujar;

   procedure Borrar (Fila, Columna : Integer) is
   begin
      Pantalla.Limpiar (Fila, Columna);
   end Borrar;

   -- Dibuja una nave completa (### arriba, # abajo al centro)
   procedure Dibujar_Nave (Fila, Columna : Integer) is
   begin
      Dibujar (Fila,     Columna,     '#');
      Dibujar (Fila,     Columna + 1, '#');
      Dibujar (Fila,     Columna + 2, '#');
      Dibujar (Fila + 1, Columna + 1, '#');
   end Dibujar_Nave;

   procedure Borrar_Nave (Fila, Columna : Integer) is
   begin
      Borrar (Fila,     Columna);
      Borrar (Fila,     Columna + 1);
      Borrar (Fila,     Columna + 2);
      Borrar (Fila + 1, Columna + 1);
   end Borrar_Nave;

   -- ============================================================
   -- INPUT NO BLOQUEANTE (termios via C)
   -- ============================================================
   type Buf_Terminal is array (1 .. 60) of Interfaces.C.unsigned_char;
   Terminal_Original : Buf_Terminal;

   function Tcgetattr (Fd : int; P : access Buf_Terminal) return int;
   pragma Import (C, Tcgetattr, "tcgetattr");

   function Tcsetattr (Fd, Accion : int; P : access Buf_Terminal) return int;
   pragma Import (C, Tcsetattr, "tcsetattr");

   function Fcntl_Leer (Fd, Cmd : int) return int;
   pragma Import (C, Fcntl_Leer, "fcntl");

   function Fcntl_Escribir (Fd, Cmd, Arg : int) return int;
   pragma Import (C, Fcntl_Escribir, "fcntl");

   function Leer_Byte (Fd  : int;
                       Buf : access Interfaces.C.unsigned_char;
                       N   : int) return int;
   pragma Import (C, Leer_Byte, "read");

   procedure Iniciar_Terminal is
      R      : int;
      Actual : aliased Buf_Terminal;
      Raw    : aliased Buf_Terminal;
      Flags  : Unsigned_32;
   begin
      R := Tcgetattr (0, Actual'Access);
      Terminal_Original := Actual;
      Raw := Actual;
      Raw (13) := Raw (13)
                  and not Interfaces.C.unsigned_char (2)   -- sin ICANON
                  and not Interfaces.C.unsigned_char (8);  -- sin ECHO
      Raw (17) := 1;  -- VMIN
      Raw (16) := 0;  -- VTIME
      R     := Tcsetattr (0, 0, Raw'Access);
      Flags := Unsigned_32 (Fcntl_Leer (0, 3));
      R     := Fcntl_Escribir (0, 4, int (Flags or 2048));  -- O_NONBLOCK
   end Iniciar_Terminal;

   procedure Restaurar_Terminal is
      R     : int;
      Ori   : aliased Buf_Terminal := Terminal_Original;
      Flags : Unsigned_32;
   begin
      Flags := Unsigned_32 (Fcntl_Leer (0, 3));
      R := Fcntl_Escribir (0, 4, int (Flags and (not Unsigned_32 (2048))));
      R := Tcsetattr (0, 0, Ori'Access);
   end Restaurar_Terminal;

   function Leer_Tecla return Character is
      Ch  : aliased Interfaces.C.unsigned_char := 0;
      Ret : int;
   begin
      Ret := Leer_Byte (0, Ch'Access, 1);
      if Ret = 1 then return Character'Val (Integer (Ch));
      else            return ASCII.NUL;
      end if;
   end Leer_Tecla;

   -- ============================================================
   -- ESTADO COMPARTIDO
   --
   -- Ademas del canon y el fin de juego, guarda la posicion de
   -- cada nave (fila y columna) para detectar colisiones por
   -- posicion real. Cada nave actualiza su posicion al moverse.
   -- ============================================================
   type Pos_Naves   is array (1 .. TOTAL_NAVES) of Integer;
   type Vivas_Naves is array (1 .. TOTAL_NAVES) of Boolean;

   protected Juego is
      -- Canon
      function  Columna_Canon return Integer;
      procedure Mover_Canon (Direccion : Integer);
      -- Fin de juego
      function  Corriendo return Boolean;
      procedure Terminar;
      function  Naves_Vivas return Integer;
      -- Naves: posicion y colision
      procedure Set_Pos_Nave (Id, Fila, Columna : Integer);
      procedure Matar_Nave (Id : Integer);
      -- Devuelve el id de la nave que ocupa (Fila,Columna), o 0 si ninguna
      function  Nave_En (Fila, Columna : Integer) return Integer;
   private
      Col_Canon  : Integer := ANCHO / 2;
      En_Juego   : Boolean := True;
      Vivas      : Integer := TOTAL_NAVES;
      Fila_Nave  : Pos_Naves := (others => 0);
      Col_Nave   : Pos_Naves := (others => 0);
      Viva_Nave  : Vivas_Naves := (others => True);
   end Juego;

   protected body Juego is
      function Columna_Canon return Integer is (Col_Canon);

      procedure Mover_Canon (Direccion : Integer) is
         Nueva : constant Integer := Col_Canon + Direccion;
      begin
         if Nueva >= 2 and then Nueva <= ANCHO - 3 then
            Col_Canon := Nueva;
         end if;
      end Mover_Canon;

      function  Corriendo   return Boolean is (En_Juego);
      procedure Terminar    is begin En_Juego := False; end Terminar;
      function  Naves_Vivas return Integer  is (Vivas);

      procedure Set_Pos_Nave (Id, Fila, Columna : Integer) is
      begin
         Fila_Nave (Id) := Fila;
         Col_Nave  (Id) := Columna;
      end Set_Pos_Nave;

      procedure Matar_Nave (Id : Integer) is
      begin
         if Viva_Nave (Id) then
            Viva_Nave (Id) := False;
            Vivas := Vivas - 1;
            if Vivas = 0 then En_Juego := False; end if;
         end if;
      end Matar_Nave;

      -- Una nave ocupa: (Fila,Col),(Fila,Col+1),(Fila,Col+2),(Fila+1,Col+1)
      function Nave_En (Fila, Columna : Integer) return Integer is
         F, C : Integer;
      begin
         for Id in 1 .. TOTAL_NAVES loop
            if Viva_Nave (Id) then
               F := Fila_Nave (Id);
               C := Col_Nave (Id);
               if (Fila = F and then Columna >= C and then Columna <= C + 2)
                  or else (Fila = F + 1 and then Columna = C + 1)
               then
                  return Id;
               end if;
            end if;
         end loop;
         return 0;
      end Nave_En;
   end Juego;

   -- ============================================================
   -- TASK TYPE NAVE
   --
   -- entry Iniciar : recibe id, fila y columna al arrancar
   -- entry Mover   : la Coordinadora le indica su nueva columna
   -- entry Impacto : rendezvous con la bala (colision)
   -- ============================================================
   task type Nave is
      entry Iniciar (Id_Ini, Fila_Ini, Columna_Ini : Integer);
      entry Mover   (Nueva_Columna : Integer);
      entry Impacto;
   end Nave;

   type Fila_De_Naves is array (1 .. NAVES_X_FILA) of Nave;
   Fila_1 : Fila_De_Naves;
   Fila_2 : Fila_De_Naves;

   task body Nave is
      Id      : Integer;
      Fila    : Integer;
      Columna : Integer;
      Viva    : Boolean := True;
   begin
      accept Iniciar (Id_Ini, Fila_Ini, Columna_Ini : Integer) do
         Id      := Id_Ini;
         Fila    := Fila_Ini;
         Columna := Columna_Ini;
      end Iniciar;

      Juego.Set_Pos_Nave (Id, Fila, Columna);
      Dibujar_Nave (Fila, Columna);
      Ada.Text_IO.Flush;

      while Viva and then Juego.Corriendo loop
         select
            -- Rendezvous con la bala
            accept Impacto;
            Borrar_Nave (Fila, Columna);
            Ada.Text_IO.Flush;
            Juego.Matar_Nave (Id);
            Viva := False;
         or
            -- Coordinadora indica nueva columna
            accept Mover (Nueva_Columna : Integer) do
               Borrar_Nave (Fila, Columna);
               Columna := Nueva_Columna;
               Juego.Set_Pos_Nave (Id, Fila, Columna);
               Dibujar_Nave (Fila, Columna);
               Ada.Text_IO.Flush;
            end Mover;
         end select;
      end loop;
   end Nave;

   -- ============================================================
   -- TASK COORDINADORA
   -- Mueve el bloque completo de naves cada 0.3 segundos.
   -- ============================================================
   task Coordinadora;

   task body Coordinadora is
      Base      : Integer := 4;
      Direccion : Integer := 1;
   begin
      -- Inicializar: id 1..6 fila superior, id 7..12 fila inferior
      for N in 1 .. NAVES_X_FILA loop
         Fila_1 (N).Iniciar (N,               FILA_NAVES_1,
                             Base + (N - 1) * SEPARACION);
         Fila_2 (N).Iniciar (N + NAVES_X_FILA, FILA_NAVES_2,
                             Base + (N - 1) * SEPARACION);
      end loop;

      while Juego.Corriendo loop
         delay 0.3;

         if Direccion = 1 and then
            Base + (NAVES_X_FILA - 1) * SEPARACION + 2 >= ANCHO - 1
         then
            Direccion := -1;
         elsif Direccion = -1 and then Base <= 2 then
            Direccion := 1;
         end if;

         Base := Base + Direccion;

         for N in 1 .. NAVES_X_FILA loop
            -- Mover nave de fila 1 (si ya murio, ignorar Tasking_Error)
            begin
               select
                  Fila_1 (N).Mover (Base + (N - 1) * SEPARACION);
               else
                  null;
               end select;
            exception
               when others => null;  -- nave terminada, seguir
            end;

            -- Mover nave de fila 2
            begin
               select
                  Fila_2 (N).Mover (Base + (N - 1) * SEPARACION);
               else
                  null;
               end select;
            exception
               when others => null;
            end;
         end loop;
      end loop;
   end Coordinadora;

   -- ============================================================
   -- TASK TYPE BALA
   -- Sube de abajo hacia arriba. En cada paso pregunta al estado
   -- si hay una nave en su posicion; si la hay, hace rendezvous
   -- SOLO con esa nave.
   -- ============================================================
   task type Bala (Columna_Ini : Integer);

   task body Bala is
      Fila   : Integer := FILA_CANON - 1;
      Golpeo : Boolean := False;
      Id     : Integer;
   begin
      while Fila >= 2 and then Juego.Corriendo and then not Golpeo loop
         Dibujar (Fila, Columna_Ini, '|');
         Ada.Text_IO.Flush;
         delay 0.05;
         Borrar (Fila, Columna_Ini);

         -- ¿Hay una nave en mi posicion?
         Id := Juego.Nave_En (Fila, Columna_Ini);
         if Id /= 0 then
            -- Rendezvous con la nave correcta (protegido por si justo murio)
            begin
               if Id <= NAVES_X_FILA then
                  select
                     Fila_1 (Id).Impacto;
                     Golpeo := True;
                  else null;
                  end select;
               else
                  select
                     Fila_2 (Id - NAVES_X_FILA).Impacto;
                     Golpeo := True;
                  else null;
                  end select;
               end if;
            exception
               when others => null;
            end;
         end if;

         Fila := Fila - 1;
      end loop;
      Ada.Text_IO.Flush;
   end Bala;

   type Acceso_Bala is access Bala;

   -- ============================================================
   -- TASK CANON
   -- ============================================================
   task Canon;

   task body Canon is
      Tecla : Character;
   begin
      while Juego.Corriendo loop
         Tecla := Leer_Tecla;
         case Tecla is
            when 'a' | 'A' => Juego.Mover_Canon (-1);
            when 'd' | 'D' => Juego.Mover_Canon (1);
            when 'w' | 'W' =>
               declare
                  B : Acceso_Bala;
               begin
                  B := new Bala (Columna_Ini => Juego.Columna_Canon + 1);
               end;
            when 'q' | 'Q' => Juego.Terminar;
            when others     => null;
         end case;
         delay 0.05;
      end loop;
   end Canon;

   -- ============================================================
   -- LOOP PRINCIPAL (redibujar el canon)
   -- ============================================================
   Col_Anterior : Integer := ANCHO / 2;
   Col_Actual   : Integer;

begin
   Iniciar_Terminal;
   Put (ESC & "?25l");
   Limpiar_Pantalla;
   Put (ESC & "24;1H");
   Put ("A=izq  D=der  W=disparar  Q=salir");

   Dibujar (FILA_CANON, Col_Anterior,     '/');
   Dibujar (FILA_CANON, Col_Anterior + 1, '^');
   Dibujar (FILA_CANON, Col_Anterior + 2, '\');
   Ada.Text_IO.Flush;

   while Juego.Corriendo loop
      Col_Actual := Juego.Columna_Canon;
      if Col_Actual /= Col_Anterior then
         Borrar  (FILA_CANON, Col_Anterior);
         Borrar  (FILA_CANON, Col_Anterior + 1);
         Borrar  (FILA_CANON, Col_Anterior + 2);
         Dibujar (FILA_CANON, Col_Actual,     '/');
         Dibujar (FILA_CANON, Col_Actual + 1, '^');
         Dibujar (FILA_CANON, Col_Actual + 2, '\');
         Ada.Text_IO.Flush;
         Col_Anterior := Col_Actual;
      end if;
      delay 0.05;
   end loop;

   Put (ESC & "?25h");
   Limpiar_Pantalla;
   Put (ESC & "1;1H");
   if Juego.Naves_Vivas = 0 then
      Put_Line ("Ganaste! Todas las naves destruidas.");
   else
      Put_Line ("Juego terminado.");
   end if;
   Restaurar_Terminal;

end Main;
