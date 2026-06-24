with Ada.Text_IO; use Ada.Text_IO;

procedure Main is

   -- ============================================================
   -- CONSTANTES
   -- ============================================================
   ANCHO        : constant := 80;
   ALTO         : constant := 24;
   NAVES_X_FILA : constant := 6;
   TOTAL_NAVES  : constant := NAVES_X_FILA * 2;
   FILA_NAVES_1 : constant := 3;
   FILA_NAVES_2 : constant := 6;
   FILA_CANON   : constant := ALTO - 1;
   SEPARACION   : constant := 12;
   MAX_BALAS    : constant := 6;   -- balas simultaneas (pool fijo)

   -- Secuencias ANSI
   ESC : constant String := ASCII.ESC & "[";

   procedure Limpiar_Pantalla is
   begin
      Put (ESC & "2J" & ESC & "H");
   end Limpiar_Pantalla;

   -- Tipos para el estado de las naves
   type Pos_Naves   is array (1 .. TOTAL_NAVES) of Integer;
   type Vivas_Naves is array (1 .. TOTAL_NAVES) of Boolean;

   
   task Pantalla is
      entry Poner (Fila, Columna : Integer; Car : Character);
   end Pantalla;

   task body Pantalla is
   begin
      loop
         select
            accept Poner (Fila, Columna : Integer; Car : Character) do
               declare
                  F : constant String := Integer'Image (Fila);
                  C : constant String := Integer'Image (Columna);
               begin
                  Put (ESC & F (2 .. F'Last) & ";" & C (2 .. C'Last) & "H");
                  Put (Car);
                  Put (ESC & "1;1H"); 
                  Flush;
               end;
            end Poner;
         or
            terminate;   
         end select;
      end loop;
   end Pantalla;

   -- Atajos de dibujo
   procedure Dibujar (Fila, Columna : Integer; Car : Character) is
   begin
      Pantalla.Poner (Fila, Columna, Car);
   end Dibujar;

   procedure Borrar (Fila, Columna : Integer) is
   begin
      Pantalla.Poner (Fila, Columna, ' ');
   end Borrar;

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


   task Juego is
      entry Mover_Canon   (Direccion : Integer);
      entry Columna_Canon (C : out Integer);
      entry Corriendo     (R : out Boolean);
      entry Terminar;
      entry Naves_Vivas   (N : out Integer);
      entry Set_Pos_Nave  (Id, Fila, Columna : Integer);
      entry Matar_Nave    (Id : Integer);
      entry Nave_En       (Fila, Columna : Integer; Id : out Integer);
   end Juego;

   task body Juego is
      Col_Canon : Integer     := ANCHO / 2;
      En_Juego  : Boolean     := True;
      Vivas     : Integer     := TOTAL_NAVES;
      Fila_Nave : Pos_Naves   := (others => 0);
      Col_Nave  : Pos_Naves   := (others => 0);
      Viva_Nave : Vivas_Naves := (others => True);
   begin
      loop
         select
            accept Mover_Canon (Direccion : Integer) do
               declare
                  Nueva : constant Integer := Col_Canon + Direccion;
               begin
                  if Nueva >= 2 and then Nueva <= ANCHO - 3 then
                     Col_Canon := Nueva;
                  end if;
               end;
            end Mover_Canon;
         or
            accept Columna_Canon (C : out Integer) do
               C := Col_Canon;
            end Columna_Canon;
         or
            accept Corriendo (R : out Boolean) do
               R := En_Juego;
            end Corriendo;
         or
            accept Terminar;
            En_Juego := False;
         or
            accept Naves_Vivas (N : out Integer) do
               N := Vivas;
            end Naves_Vivas;
         or
            accept Set_Pos_Nave (Id, Fila, Columna : Integer) do
               Fila_Nave (Id) := Fila;
               Col_Nave  (Id) := Columna;
            end Set_Pos_Nave;
         or
            accept Matar_Nave (Id : Integer) do
               if Viva_Nave (Id) then
                  Viva_Nave (Id) := False;
                  Vivas := Vivas - 1;
                  if Vivas = 0 then
                     En_Juego := False;
                  end if;
               end if;
            end Matar_Nave;
         or
            accept Nave_En (Fila, Columna : Integer; Id : out Integer) do
               Id := 0;
               for K in 1 .. TOTAL_NAVES loop
                  if Viva_Nave (K) then
                     if (Fila = Fila_Nave (K)
                         and then Columna >= Col_Nave (K)
                         and then Columna <= Col_Nave (K) + 2)
                        or else
                        (Fila = Fila_Nave (K) + 1
                         and then Columna = Col_Nave (K) + 1)
                     then
                        Id := K;
                     end if;
                  end if;
               end loop;
            end Nave_En;
         or
            terminate;
         end select;
      end loop;
   end Juego;

   
   task type Nave is
      entry Iniciar (Id_Ini, Fila_Ini, Columna_Ini : Integer);
      entry Mover   (Nueva_Columna : Integer);
      entry Impacto;
   end Nave;

   Fila_1 : array (1 .. NAVES_X_FILA) of Nave;
   Fila_2 : array (1 .. NAVES_X_FILA) of Nave;

  
   task type Bala is
      entry Disparar (Columna : Integer);
   end Bala;

   task body Bala is
      Col    : Integer;
      Fila   : Integer;
      Golpeo : Boolean;
      Quien  : Integer;
      Sigue  : Boolean;
   begin
      loop
         -- Esperar a ser disparada (o terminar al cerrar el juego)
         select
            accept Disparar (Columna : Integer) do
               Col := Columna;
            end Disparar;
         or
            terminate;
         end select;

         -- Volar hacia arriba
         Fila   := FILA_CANON - 1;
         Golpeo := False;
         loop
            Juego.Corriendo (Sigue);
            exit when Fila < 2 or else not Sigue or else Golpeo;

            Dibujar (Fila, Col, '|');
            delay 0.05;
            Borrar (Fila, Col);

            Juego.Nave_En (Fila, Col, Quien);
            if Quien /= 0 then
               -- Cita SOLO con la nave golpeada; condicional por si
               -- justo murio (guarda cerrada) -> simplemente no pasa.
               if Quien <= NAVES_X_FILA then
                  select
                     Fila_1 (Quien).Impacto;
                     Golpeo := True;
                  else
                     null;
                  end select;
               else
                  select
                     Fila_2 (Quien - NAVES_X_FILA).Impacto;
                     Golpeo := True;
                  else
                     null;
                  end select;
               end if;
            end if;

            Fila := Fila - 1;
         end loop;
      end loop;
   end Bala;

   Balas : array (1 .. MAX_BALAS) of Bala;

   
   task body Nave is
      Id   : Integer;
      Fila : Integer;
      Col  : Integer;
      Viva : Boolean := True;
   begin
      accept Iniciar (Id_Ini, Fila_Ini, Columna_Ini : Integer) do
         Id   := Id_Ini;
         Fila := Fila_Ini;
         Col  := Columna_Ini;
      end Iniciar;

      Juego.Set_Pos_Nave (Id, Fila, Col);
      Dibujar_Nave (Fila, Col);

      loop
         select
            when Viva =>
               accept Impacto;
               Borrar_Nave (Fila, Col);
               Juego.Matar_Nave (Id);
               Viva := False;
         or
            when Viva =>
               accept Mover (Nueva_Columna : Integer) do
                  Borrar_Nave (Fila, Col);
                  Col := Nueva_Columna;
                  Juego.Set_Pos_Nave (Id, Fila, Col);
                  Dibujar_Nave (Fila, Col);
               end Mover;
         or
            terminate;   -- nave viva o muerta: cierra al terminar el juego
         end select;
      end loop;
   end Nave;

   
   procedure Disparar_Bala is
      Col : Integer;
   begin
      Juego.Columna_Canon (Col);
      for I in Balas'Range loop
         select
            Balas (I).Disparar (Col + 1);
            return;            -- bala disparada
         else
            null;              -- ocupada, probar la siguiente
         end select;
      end loop;
   end Disparar_Bala;

   
   -- TASK COORDINADORA: mueve el bloque de naves
   task Coordinadora;

   task body Coordinadora is
      Base  : Integer := 4;
      Dir   : Integer := 1;
      Sigue : Boolean;
   begin
      -- Inicializar: id 1..6 fila superior, id 7..12 fila inferior
      for N in 1 .. NAVES_X_FILA loop
         Fila_1 (N).Iniciar (N, FILA_NAVES_1,
                             Base + (N - 1) * SEPARACION);
         Fila_2 (N).Iniciar (N + NAVES_X_FILA, FILA_NAVES_2,
                             Base + (N - 1) * SEPARACION);
      end loop;

      loop
         Juego.Corriendo (Sigue);
         exit when not Sigue;
         delay 0.3;

         if Dir = 1 and then
            Base + (NAVES_X_FILA - 1) * SEPARACION + 2 >= ANCHO - 1
         then
            Dir := -1;
         elsif Dir = -1 and then Base <= 2 then
            Dir := 1;
         end if;
         Base := Base + Dir;

         for N in 1 .. NAVES_X_FILA loop
            -- Cita condicional: si la nave murio o esta ocupada, se saltea
            select
               Fila_1 (N).Mover (Base + (N - 1) * SEPARACION);
            else
               null;
            end select;
            select
               Fila_2 (N).Mover (Base + (N - 1) * SEPARACION);
            else
               null;
            end select;
         end loop;
      end loop;
   end Coordinadora;

   
   task Canon;

   task body Canon is
      Tecla : Character;
      Sigue : Boolean;
   begin
      loop
         Get_Immediate (Tecla);   -- bloquea hasta una tecla; sin echo
         Pantalla.Poner (1, 1, ' ');  -- borra eco residual y reaparca cursor
         case Tecla is
            when 'a' | 'A' => Juego.Mover_Canon (-1);
            when 'd' | 'D' => Juego.Mover_Canon (1);
            when 'w' | 'W' => Disparar_Bala;
            when 'q' | 'Q' => Juego.Terminar;
                              exit;        -- salir de inmediato
            when others    => null;
         end case;
         -- Si el juego ya termino por otra via (todas las naves muertas)
         Juego.Corriendo (Sigue);
         exit when not Sigue;
      end loop;
   end Canon;

   -- ============================================================
   -- VARIABLES DEL LOOP PRINCIPAL
   -- ============================================================
   Col_Anterior : Integer := ANCHO / 2;
   Col_Actual   : Integer;
   Sigue        : Boolean;
   Vivas        : Integer;

begin
   Put (ESC & "?25l");   
   Limpiar_Pantalla;
   Put (ESC & "24;1H");
   Put ("A=izq  D=der  W=disparar  Q=salir");

   Dibujar (FILA_CANON, Col_Anterior,     '/');
   Dibujar (FILA_CANON, Col_Anterior + 1, '^');
   Dibujar (FILA_CANON, Col_Anterior + 2, '\');

   loop
      Juego.Corriendo (Sigue);
      exit when not Sigue;

      Juego.Columna_Canon (Col_Actual);
      if Col_Actual /= Col_Anterior then
         Borrar  (FILA_CANON, Col_Anterior);
         Borrar  (FILA_CANON, Col_Anterior + 1);
         Borrar  (FILA_CANON, Col_Anterior + 2);
         Dibujar (FILA_CANON, Col_Actual,     '/');
         Dibujar (FILA_CANON, Col_Actual + 1, '^');
         Dibujar (FILA_CANON, Col_Actual + 2, '\');
         Col_Anterior := Col_Actual;
      end if;
      delay 0.05;
   end loop;

   delay 0.1;                 -- dejar terminar dibujos pendientes
   Put (ESC & "?25h");        -- mostrar cursor
   Limpiar_Pantalla;
   Put (ESC & "2;1H");        -- fila 2: la fila 1 es el sumidero del cursor

   Juego.Naves_Vivas (Vivas);
   if Vivas = 0 then
      Put_Line ("Ganaste! Todas las naves destruidas.");
      Put_Line ("(presiona una tecla para salir)");
   else
      Put_Line ("Juego terminado.");
   end if;
end Main;