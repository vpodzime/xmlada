with Schema.Validators;       use Schema.Validators;
with Ada.Characters.Handling; use Ada.Characters.Handling;

package body Schema.Date_Time is

   procedure Parse (Ch : String; Date     : out Date_NZ_T;  Eos : out Natural);
   procedure Parse (Ch : String; Time     : out Time_NZ_T;  Eos : out Natural);
   procedure Parse (Ch : String; TZ       : out Timezone_T);
   --  Parse the various components of dates.
   --  On exit, Eos is set to the first unused character in Ch, except for the
   --  timezone which must finish on the last character in Ch.

   function Image (Date : Date_NZ_T) return String;
   function Image (TZ : Timezone_T)  return String;
   function Image (Time : Time_NZ_T) return String;
   --  Return the string representation of the parameter.

   type Compare_Result is (Less_Than, Equal, Greater_Than, Uncomparable);

   function Compare (Time1, Time2 : Date_Time_T)        return Compare_Result;
   function Compare (Date1, Date2 : Date_NZ_T)          return Compare_Result;
   function Compare (Time1, Time2 : Time_NZ_T)          return Compare_Result;
   function Compare (Duration1, Duration2 : Duration_T) return Compare_Result;
   --  Compare the two parameters. The parameters must have been normalized
   --  prior to the call. Timezones are taken into account if present

   function Normalize (Date : Date_Time_T)    return Date_Time_T;
   function Normalize (Duration : Duration_T) return Duration_T;
   --  Return a normalized version of Date, ie with a time zone of 0. There
   --  will be no time zone set for the result if Date has no timezone

   procedure Normalize (Date     : in out Date_NZ_T);
   --  Make sure that the day is valid in the date. Otherwise, change the month
   --  and year until we end up on a valid day

   function Image (Value : Integer; Num_Digits : Natural := 2) return String;
   --  Return the image of Value, in a string of Num_Digits characters long

   function MS_Image (Sub_Second : Day_Range) return String;
   --  Return the image to use for milliseconds (nothing if 0, or the minimal
   --  number of digits)

   generic
      Field : Integer;
      Char  : Character;
   function Component_Image return String;
   --  Return each component of the duration, in the format expected for
   --  durations. Nothing is returned if the matching component is
   --  null;

   function Max_Days_In_Month (Year, Month : Integer) return Integer;
   --  Return the maximum number of days in the given month. Month is
   --  allowed to be outside the range 1 .. 12

   generic
      type T is private;
      with function Normalize (T1 : T) return T is <>;
      with function Compare (T1, T2 : T) return Compare_Result is <>;
   package Comparators is
      function "<"  (T1, T2 : T) return Boolean;
      function "<=" (T1, T2 : T) return Boolean;
      function "="  (T1, T2 : T) return Boolean;
      function ">"  (T1, T2 : T) return Boolean;
      function ">=" (T1, T2 : T) return Boolean;
   end Comparators;
   --  Generate the comparison functions for various types

   -----------
   -- Image --
   -----------

   function Image (Value : Integer; Num_Digits : Natural := 2) return String is
      Str : constant String := Integer'Image (Value);
      Padding : constant String (1 .. Num_Digits) := (others => '0');
   begin
      if Value < 0 then
         if Str'Length - 1 > Num_Digits then
            --  No padding, return the whole string
            return Str;
         else
            return '-' & Padding (1 .. Num_Digits - Str'Last + Str'First)
              & Str (Str'First + 1 .. Str'Last);
         end if;
      else
         if Str'Length - 1 > Num_Digits then
            return Str (Str'First + 1 .. Str'Last);
         else
            return Padding (1 .. Num_Digits - Str'Last + Str'First)
              & Str (Str'First + 1 .. Str'Last);
         end if;
      end if;
   end Image;

   ---------------------
   -- Component_Image --
   ---------------------

   function Component_Image return String is
   begin
      if Field = 0 then
         return "";
      else
         return Image (abs (Field), 1) & Char;
      end if;
   end Component_Image;

   -----------
   -- Image --
   -----------

   function Image (Date : Date_NZ_T) return String is
   begin
      return Image (Date.Year, 4)
        & '-' & Image (abs (Date.Month), 2) & '-'
        & Image (abs (Date.Day), 2);
   end Image;

   -----------
   -- Image --
   -----------

   function Image (Date : Date_T) return String is
   begin
      return Image (Date.Date) & Image (Date.TZ);
   end Image;

   --------------
   -- MS_Image --
   --------------

   function MS_Image (Sub_Second : Day_Range) return String is
      Sub : constant String := Day_Range'Image (Sub_Second);
      Last : Natural := Sub'Last;
   begin
      if Sub_Second = 0.0 then
         return "";
      else
         while Last >= Sub'First and Sub (Last) = '0' loop
            Last := Last - 1;
         end loop;

         --  Skip '0.' in the subseconds image
         return Sub (Sub'First + 2 .. Last);
      end if;
   end MS_Image;

   -----------
   -- Image --
   -----------

   function Image (Time : Time_NZ_T) return String is
      Hour, Min, Secs : Natural;
      Sub_Second      : Time_NZ_T;
   begin
      if Time = 0.0 then
         Secs := 0;
      else
         Secs := Natural (abs (Time) - 0.5);
      end if;

      Sub_Second := abs (Time) - Time_NZ_T (Secs);
      Hour       := Integer (Secs / 3600);
      Secs       := Secs mod 3600;
      Min        := Integer (Secs / 60);
      Secs       := Secs mod 60;

      return Image (Hour, 2) & ':' & Image (Min, 2)
        & ':' & Image (Secs, 2) & MS_Image (Sub_Second);
   end Image;

   -----------
   -- Image --
   -----------

   function Image (Time : Time_T) return String is
   begin
      return Image (Time.Time) & Image (Time.TZ);
   end Image;

   -----------
   -- Image --
   -----------

   function Image (Duration : Duration_T) return String is
      Hour, Min, Secs : Natural;
      Sub_Second      : Time_NZ_T;

      function Year_Image  is new Component_Image (Duration.Year, 'Y');
      function Month_Image is new Component_Image (Duration.Month, 'M');
      function Day_Image   is new Component_Image (Duration.Day, 'D');
      function Secs_Image return String;

      function Secs_Image return String is
         Im : constant String := Image (Secs, 1) & MS_Image (Sub_Second) & 'S';
      begin
         if Im /= "0S" then
            return Im;
         else
            return "";
         end if;
      end Secs_Image;

   begin
      if Duration.Seconds = 0.0 then
         Secs := 0;
      else
         Secs := Natural (abs (Duration.Seconds) - 0.5);
      end if;

      Sub_Second := abs (Duration.Seconds) - Time_NZ_T (Secs);
      Hour       := Integer (Secs / 3600);
      Secs       := Secs mod 3600;
      Min        := Integer (Secs / 60);
      Secs       := Secs mod 60;

      declare
         function Hour_Image  is new Component_Image (Hour, 'H');
         function Min_Image   is new Component_Image (Min, 'M');
         Date_Img : constant String := Year_Image & Month_Image & Day_Image;
         Time_Img : constant String := Hour_Image & Min_Image & Secs_Image;
      begin
         if Duration.Sign < 0 then
            if Time_Img'Length /= 0 then
               return "-P" & Date_Img & 'T' & Time_Img;
            else
               return "-P" & Date_Img;
            end if;
         else
            if Time_Img'Length /= 0 then
               return 'P' & Date_Img & 'T' & Time_Img;
            else
               return 'P' & Date_Img;
            end if;
         end if;
      end;
   end Image;

   -----------
   -- Image --
   -----------

   function Image (TZ : Timezone_T) return String is
   begin
      if TZ = No_Timezone then
         return "";
      elsif TZ = 0 then
         return "Z";
      elsif TZ < 0 then
         return '-' & Image (abs (Integer (TZ)) / 60, 2) & ':'
           & Image (abs (Integer (TZ)) mod 60, 2);
      else
         return '+' & Image (abs (Integer (TZ)) / 60, 2) & ':'
           & Image (abs (Integer (TZ)) mod 60, 2);
      end if;
   end Image;

   -----------
   -- Image --
   -----------

   function Image (Date : Date_Time_T) return String is
   begin
      return Image (Date.Date) & 'T' & Image (Date.Time) & Image (Date.TZ);
   end Image;

   -----------
   -- Parse --
   -----------

   procedure Parse
     (Ch   : String;
      Date : out Date_NZ_T;
      Eos  : out Natural)
   is
      Pos  : Integer := Ch'First;
   begin
      if Ch (Pos) = '-' then
         Pos := Pos + 1;
      end if;

      while Pos <= Ch'Last and then Ch (Pos) /= '-' loop
         Pos := Pos + 1;
      end loop;

      if Ch (Pos) /= '-'
        or else Ch (Pos + 3) /= '-'
        or else (Pos + 6 <= Ch'Last and then Ch (Pos + 6) /= 'T')
      then
         Validation_Error ("Invalid separator in date value """ & Ch & """");
         Date := No_Date_NZ;
         return;
      end if;

      Date.Year   := Integer'Value (Ch (Ch'First .. Pos - 1));
      Date.Month  := Integer'Value (Ch (Pos +  1 .. Pos +  2));
      Date.Day    := Integer'Value (Ch (Pos +  4 .. Pos +  5));
      Eos := Pos + 6;

      if Date.Year = 0 then
         Validation_Error ("Year cannot be null in: """ & Ch & """");
         Date := No_Date_NZ;
         return;
      end if;

   exception
      when Constraint_Error =>
         Validation_Error ("Invalid date """ & Ch & """");
         Date := No_Date_NZ;
         Eos  := Ch'Last + 1;
   end Parse;

   -----------
   -- Parse --
   -----------

   procedure Parse
     (Ch   : String;
      Time : out Time_NZ_T;
      Eos  : out Natural)
   is
      --  Format is "hh:mm:ss.sss[+-]hh:mm"
      Dur : Time_NZ_T;
      Pos : Integer;
      Hour, Min : Integer;
      Msec : Day_Range := 0.0;
   begin
      Hour := Integer'Value (Ch (Ch'First .. Ch'First + 1));
      Dur  := Day_Range (Hour) * 3600.0;

      if Ch (Ch'First + 2) /= ':'
        or else Ch (Ch'First + 5) /= ':'
      then
         Validation_Error ("Invalid separator in time: """ & Ch & """");
         Time := No_Time_NZ;
         return;
      end if;

      Min := Integer'Value (Ch (Ch'First + 3 .. Ch'First + 4));
      Dur := Dur + Day_Range (Min) * 60.0;

      if Min > 59 then
         Validation_Error
           ("Invalid minutes specification in time: """ & Ch & """");
         Time := No_Time_NZ;
         return;
      end if;

      Pos := Ch'First + 8;
      if Pos = Ch'Last and then Ch (Pos) = '.' then
         Validation_Error ("'.' must be followed by digits in """ & Ch & """");
      end if;

      if Pos < Ch'Last and then Ch (Pos) = '.' then
         Pos := Pos + 1;
         while Pos <= Ch'Last and then Is_Decimal_Digit (Ch (Pos)) loop
            Pos := Pos + 1;
         end loop;

         Msec := Day_Range'Value (Ch (Ch'First + 6 .. Pos - 1));
         Eos := Pos;
      else
         Msec := Day_Range'Value (Ch (Ch'First + 6 .. Ch'First + 7));
         Eos := Ch'First + 8;
      end if;

      Time := Dur + Msec;

      if Hour > 24
        or else (Hour = 24 and then (Min /= 0 or else Msec /= 0.0))
      then
         Validation_Error
           ("Invalid hour specification in time: """ & Ch & """");
         Time := No_Time_NZ;
         return;
      end if;

   exception
      when Constraint_Error =>
         Validation_Error ("Invalid time: """ & Ch & """");
         Time := No_Time_NZ;
         Eos  := Ch'Last + 1;
   end Parse;

   -----------
   -- Parse --
   -----------

   procedure Parse
     (Ch : String;
      TZ : out Timezone_T) is
   begin
      if Ch'Length /= 0 then
         if Ch (Ch'First) = 'Z' then
            if Ch'Length /= 1 then
               Validation_Error ("Invalid time zone in """ & Ch & """");
               TZ := No_Timezone;
               return;
            else
               TZ := 0;
            end if;

         elsif Ch'Length /= 6 then
            Validation_Error ("Invalid time zone in """ & Ch & """");
            TZ := No_Timezone;
            return;

         else
            if (Ch (Ch'First) /= '-' and then Ch (Ch'First) /= '+')
              or else Ch (Ch'First + 3) /= ':'
            then
               Validation_Error
                 ("Invalid time zone specification in """ & Ch & """");
               TZ := No_Timezone;
               return;
            end if;

            TZ :=
              Timezone_T'Value (Ch (Ch'First + 1 .. Ch'First + 2)) * 60
              + Timezone_T'Value (Ch (Ch'First + 4 .. Ch'First + 5));

            if abs (TZ) > 14 * 60 then
               Validation_Error ("Invalid time zone range in """ & Ch & """");
               TZ := No_Timezone;
               return;
            end if;

            if Ch (Ch'First) = '-' then
               TZ := -TZ;
            end if;
         end if;
      else
         TZ := No_Timezone;
      end if;
   exception
      when Constraint_Error =>
         Validation_Error
           ("Invalid time zone specification in """ & Ch & """");
         TZ := No_Timezone;
   end Parse;

   -----------
   -- Value --
   -----------

   function Value (Ch : String) return Duration_T is
      Result : Duration_T := No_Duration;
      Pos    : Integer := Ch'First;
      Tmp    : Integer;
      Processing_Time : Boolean := False;
   begin
      if Ch (Pos) = '-' then
         Result.Sign := -1;
         Pos := Pos + 1;
      else
         Result.Sign := 1;
      end if;

      if Ch (Pos) /= 'P' then
         Validation_Error ("Invalid prefix for duration in """ & Ch & """");
         return No_Duration;
      end if;

      while Pos <= Ch'Last loop
         Tmp := Pos;
         while Tmp <= Ch'Last
           and then (Is_Decimal_Digit (Ch (Tmp)) or else Ch (Tmp) = '.')
         loop
            Tmp := Tmp + 1;
         end loop;

         if Ch (Tmp) = 'T' then
            Processing_Time := True;
            if Tmp = Ch'Last then
               Validation_Error ("Expecting time after T in """ & Ch & """");
            end if;

         elsif Ch (Tmp) = 'Y' then
            if Processing_Time then
               Validation_Error ("Expecting time component in """ & Ch & """");
               return No_Duration;
            end if;

            Result.Year := Integer'Value (Ch (Pos .. Tmp - 1));

         elsif Ch (Tmp) = 'M' then
            if Processing_Time then
               Result.Seconds := Result.Seconds + Day_Range
                 (Integer'Value (Ch (Pos .. Tmp - 1))) * 60.0;
            else
               Result.Month := Integer'Value (Ch (Pos .. Tmp - 1));
            end if;

         elsif Ch (Tmp) = 'D' then
            if Processing_Time then
               Validation_Error ("Expecting time component in """ & Ch & """");
               return No_Duration;
            end if;

            Result.Day := Integer'Value (Ch (Pos .. Tmp - 1));

         elsif Ch (Tmp) = 'S' then
            if not Processing_Time then
               Validation_Error ("Expecting date component in """ & Ch & """");
               return No_Duration;
            end if;

            Result.Seconds := Result.Seconds
              + Day_Range'Value (Ch (Pos .. Tmp - 1));

         elsif Ch (Tmp) = 'H' then
            if not Processing_Time then
               Validation_Error ("Expecting date component in """ & Ch & """");
               return No_Duration;
            end if;
            Result.Seconds := Result.Seconds + Day_Range
              (Integer'Value (Ch (Pos .. Tmp - 1))) * 3600.0;
         end if;

         Pos := Tmp + 1;
      end loop;

      return Result;
   end Value;

   -----------
   -- Value --
   -----------

   function Value (Ch : String) return Date_Time_T is
      Result : Date_Time_T;
      Eos    : Integer;
   begin
      Parse (Ch, Result.Date, Eos);

      if Ch (Eos) /= 'T' then
         Validation_Error ("Invalid date/time separator in """ & Ch & """");
         return No_Date_Time;
      end if;

      Parse (Ch (Eos + 1 .. Ch'Last), Result.Time, Eos);
      Parse (Ch (Eos .. Ch'Last), Result.TZ);
      return Result;
   end Value;

   -----------
   -- Value --
   -----------

   function Value (Ch : String) return Date_T is
      Result : Date_T;
      Eos    : Integer;
   begin
      Parse (Ch, Result.Date, Eos);
      Parse (Ch (Eos .. Ch'Last), Result.TZ);
      return Result;
   end Value;

   -----------
   -- Value --
   -----------

   function Value (Ch : String) return Time_T is
      Result : Time_T;
      Eos    : Integer;
   begin
      Parse (Ch, Result.Time, Eos);
      Parse (Ch (Eos .. Ch'Last), Result.TZ);
      return Result;
   end Value;

   -----------------------
   -- Max_Days_In_Month --
   -----------------------

   function Max_Days_In_Month (Year, Month : Integer) return Integer is
      Days : constant array (1 .. 12) of Integer :=
        (1 => 31, 2 => 28,  3 => 31,  4 => 30, 5 => 31, 6 => 30, 7 => 31,
         8 => 31, 9 => 30, 10 => 31, 11 => 30, 12 => 31);
      Y : constant Integer := Year
        + Integer (Float'Floor (Float (Month - 1) / 12.0));
      M : constant Integer := 1 + (Month - 1) mod 12;

   begin
      if M = 2 then
         if Y mod 400 = 0
           or else (Y mod 100 /= 0 and then Y mod 4 = 0)
         then
            return 29;
         else
            return 28;
         end if;
      else
         return Days (M);
      end if;
   end Max_Days_In_Month;

   ---------
   -- "+" --
   ---------

   function "+"
     (Date : Date_Time_T; Duration : Duration_T) return Date_Time_T
   is
      Result : Date_Time_T := Date;
      Tmp    : Float;
      Tmp2   : Integer;
   begin
      Result.Date.Month :=
        Date.Date.Month + Duration.Sign * Duration.Month;
      Result.Date.Year  :=
        Date.Date.Year  + Duration.Sign * Duration.Year;
      Result.Date.Day   :=
        Date.Date.Day   + Duration.Sign * Duration.Day;
      Result.TZ           := Date.TZ;

      Tmp := Float (Date.Time)
        + Float (Duration.Sign) * Float (Duration.Seconds);
      if Tmp < 0.0 or else Tmp > 86_400.0 then
         Tmp2                     := Integer (Float'Floor (Tmp / 86_400.0));
         Result.Time     := Day_Range (Tmp - Float (Tmp2 * 86_400));
         Result.Date.Day := Result.Date.Day + Tmp2;
      else
         --  Redo the computation based on the Duration type, to avoid
         --  rounding error. We know for sur the result will be in the range
         Result.Time := Date.Time
           + Day_Range (Duration.Sign) * Day_Range (Duration.Seconds);
      end if;

      Normalize (Result.Date);
      return Result;
   end "+";

   ---------------
   -- Normalize --
   ---------------

   procedure Normalize (Date : in out Date_NZ_T) is
      Carry    : Integer;
      Max_Days : Integer;
   begin
      if Date.Month < 1 or else Date.Month > 12 then
         Date.Year := Date.Year + (Date.Month - 1) / 12;
         Date.Month := (Date.Month - 1) mod 12 + 1;
      end if;

      loop
         if Date.Day < 1 then
            Date.Day := Date.Day
              + Max_Days_In_Month (Date.Year, Date.Month - 1);
            Carry := -1;
         else
            Max_Days := Max_Days_In_Month (Date.Year, Date.Month);
            if Date.Day > Max_Days then
               Date.Day := Date.Day - Max_Days;
               Carry := 1;
            else
               exit;
            end if;
         end if;

         Date.Year := Date.Year
           + Integer (Float'Floor (Float (Date.Month + Carry - 1) / 12.0));
         Date.Month := 1 + (Date.Month + Carry - 1) mod 12;
      end loop;
   end Normalize;

   ---------------
   -- Normalize --
   ---------------

   function Normalize (Date : Date_Time_T) return Date_Time_T is
      Result : Date_Time_T;
   begin
      if Date.TZ /= No_Timezone and then Date.TZ /= 0 then
         if Date.TZ > 0 then
            Result := Date + (-1, 0, 0, 0, Day_Range (Date.TZ * 60));
         else
            Result := Date + (1, 0, 0, 0, Day_Range (-Date.TZ * 60));
         end if;
         Result.TZ := 0;
         return Result;
      else
         return Date;
      end if;
   end Normalize;

   ---------------
   -- Normalize --
   ---------------

   function Normalize (Duration : Duration_T) return Duration_T is
   begin
      return Duration;
   end Normalize;

   -------------
   -- Compare --
   -------------

   function Compare (Date1, Date2 : Date_NZ_T) return Compare_Result is
   begin
      if Date1.Year < Date2.Year then
         return Less_Than;
      elsif Date1.Year > Date2.Year then
         return Greater_Than;

      elsif Date1.Month < Date2.Month then
         return Less_Than;
      elsif Date1.Month > Date2.Month then
         return Greater_Than;

      elsif Date1.Day < Date2.Day then
         return Less_Than;
      elsif Date1.Day > Date2.Day then
         return Greater_Than;
      end if;

      return Equal;
   end Compare;

   -------------
   -- Compare --
   -------------

   function Compare (Time1, Time2 : Time_NZ_T) return Compare_Result is
   begin
      if Time1 < Time2 then
         return Less_Than;
      elsif Time1 > Time2 then
         return Greater_Than;
      else
         return Equal;
      end if;
   end Compare;

   -------------
   -- Compare --
   -------------

   function Compare
     (Duration1, Duration2 : Duration_T) return Compare_Result
   is
      --  See 3.2.6.2 for more information on how to compare Durations
      Date1 : constant Date_Time_T := ((1696, 09, 01), 0.0, 0);
      Date2 : constant Date_Time_T := ((1697, 02, 01), 0.0, 0);
      Date3 : constant Date_Time_T := ((1903, 03, 01), 0.0, 0);
      Date4 : constant Date_Time_T := ((1903, 07, 01), 0.0, 0);
      T1 : constant Compare_Result :=
        Compare (Normalize (Date1 + Duration1), Normalize (Date1 + Duration2));
      T2 : constant Compare_Result :=
        Compare (Normalize (Date2 + Duration1), Normalize (Date2 + Duration2));
      T3 : constant Compare_Result :=
        Compare (Normalize (Date3 + Duration1), Normalize (Date3 + Duration2));
      T4 : constant Compare_Result :=
        Compare (Normalize (Date4 + Duration1), Normalize (Date4 + Duration2));

   begin
      if T1 = Less_Than
        and then T2 = Less_Than
        and then T3 = Less_Than
        and then T4 = Less_Than
      then
         return Less_Than;

      elsif T1 = Greater_Than
        and then T2 = Greater_Than
        and then T3 = Greater_Than
        and then T4 = Greater_Than
      then
         return Greater_Than;

      elsif T1 = Equal
        and then T2 = Equal
        and then T3 = Equal
        and then T4 = Equal
      then
         return Equal;

      else
         return Uncomparable;
      end if;
   end Compare;

   -------------
   -- Compare --
   -------------

   function Compare (Time1, Time2 : Date_Time_T) return Compare_Result is
      T  : Date_Time_T;
      Tmp : Compare_Result;
   begin
      if (Time1.TZ = No_Timezone and Time2.TZ = No_Timezone)
        or else (Time1.TZ /= No_Timezone and Time2.TZ /= No_Timezone)
      then
         Tmp := Compare (Time1.Date, Time2.Date);
         if Tmp /= Equal then
            return Tmp;
         else
            return Compare (Time1.Time, Time2.Time);
         end if;

      elsif Time1.TZ /= No_Timezone then
         T := Time2;
         T.TZ := 14 * 60;
         if Compare (Time1, Normalize (T)) = Less_Than then
            return Less_Than;
         end if;

         T.TZ := -14 * 60;
         if Compare (Time1, Normalize (T)) = Greater_Than then
            return Greater_Than;
         end if;

         return Uncomparable;

      else
         T := Time1;
         T.TZ := -14 * 60;
         if Compare (Normalize (T), Time2) = Less_Than then
            return Less_Than;
         end if;

         T.TZ := 14 * 60;
         if Compare (Normalize (T), Time2) = Greater_Than then
            return Greater_Than;
         end if;

         return Uncomparable;
      end if;
   end Compare;

   -----------------
   -- Comparators --
   -----------------

   package body Comparators is

      ---------
      -- "<" --
      ---------

      function "<" (T1, T2 : T)  return Boolean is
         Result : constant Compare_Result :=
           Compare (Normalize (T1), Normalize (T2));
      begin
         if Result = Uncomparable then
            raise Not_Comparable;
         else
            return Result = Less_Than;
         end if;
      end "<";

      ----------
      -- "<=" --
      ----------

      function "<=" (T1, T2 : T) return Boolean is
         Result : constant Compare_Result :=
           Compare (Normalize (T1), Normalize (T2));
      begin
         if Result = Uncomparable then
            raise Not_Comparable;
         else
            return Result = Less_Than or Result = Equal;
         end if;
      end "<=";

      ---------
      -- "=" --
      ---------

      function "=" (T1, T2 : T)  return Boolean is
         Result : constant Compare_Result :=
           Compare (Normalize (T1), Normalize (T2));
      begin
         if Result = Uncomparable then
            raise Not_Comparable;
         else
            return Result = Equal;
         end if;
      end "=";

      ---------
      -- ">" --
      ---------

      function ">" (T1, T2 : T)  return Boolean is
         Result : constant Compare_Result :=
           Compare (Normalize (T1), Normalize (T2));
      begin
         if Result = Uncomparable then
            raise Not_Comparable;
         else
            return Result = Greater_Than;
         end if;
      end ">";

      ----------
      -- ">=" --
      ----------

      function ">=" (T1, T2 : T) return Boolean is
         Result : constant Compare_Result :=
           Compare (Normalize (T1), Normalize (T2));
      begin
         if Result = Uncomparable then
            raise Not_Comparable;
         else
            return Result = Greater_Than or Result = Equal;
         end if;
      end ">=";
   end Comparators;

   ---------
   -- "<" --
   ---------

   function "<"  (Time1, Time2 : Time_T) return Boolean is
   begin
      return Date_Time_T'(No_Date_NZ, Time1.Time, Time1.TZ)
        < Date_Time_T'(No_Date_NZ, Time2.Time, Time2.TZ);
   end "<";

   ----------
   -- "<=" --
   ----------

   function "<=" (Time1, Time2 : Time_T) return Boolean is
   begin
      return Date_Time_T'(No_Date_NZ, Time1.Time, Time1.TZ)
        <= Date_Time_T'(No_Date_NZ, Time2.Time, Time2.TZ);
   end "<=";

   ---------
   -- "=" --
   ---------

   function "="  (Time1, Time2 : Time_T) return Boolean is
   begin
      return Date_Time_T'(No_Date_NZ, Time1.Time, Time1.TZ)
        = Date_Time_T'(No_Date_NZ, Time2.Time, Time2.TZ);
   end "=";

   ---------
   -- ">" --
   ---------

   function ">"  (Time1, Time2 : Time_T) return Boolean is
   begin
      return Date_Time_T'(No_Date_NZ, Time1.Time, Time1.TZ)
        > Date_Time_T'(No_Date_NZ, Time2.Time, Time2.TZ);
   end ">";

   ----------
   -- ">=" --
   ----------

   function ">=" (Time1, Time2 : Time_T) return Boolean is
   begin
      return Date_Time_T'(No_Date_NZ, Time1.Time, Time1.TZ)
        >= Date_Time_T'(No_Date_NZ, Time2.Time, Time2.TZ);
   end ">=";

   ---------
   -- "<" --
   ---------

   function "<"  (Date1, Date2 : Date_T) return Boolean is
   begin
      return Date_Time_T'(Date1.Date, No_Time_NZ, Date1.TZ)
        < Date_Time_T'(Date2.Date, No_Time_NZ, Date2.TZ);
   end "<";

   ----------
   -- "<=" --
   ----------

   function "<=" (Date1, Date2 : Date_T) return Boolean is
   begin
      return Date_Time_T'(Date1.Date, No_Time_NZ, Date1.TZ)
        <= Date_Time_T'(Date2.Date, No_Time_NZ, Date2.TZ);
   end "<=";

   ---------
   -- "=" --
   ---------

   function "="  (Date1, Date2 : Date_T) return Boolean is
   begin
      return Date_Time_T'(Date1.Date, No_Time_NZ, Date1.TZ)
        = Date_Time_T'(Date2.Date, No_Time_NZ, Date2.TZ);
   end "=";

   ---------
   -- ">" --
   ---------

   function ">"  (Date1, Date2 : Date_T) return Boolean is
   begin
      return Date_Time_T'(Date1.Date, No_Time_NZ, Date1.TZ)
        > Date_Time_T'(Date2.Date, No_Time_NZ, Date2.TZ);
   end ">";

   ----------
   -- ">=" --
   ----------

   function ">=" (Date1, Date2 : Date_T) return Boolean is
   begin
      return Date_Time_T'(Date1.Date, No_Time_NZ, Date1.TZ)
        >= Date_Time_T'(Date2.Date, No_Time_NZ, Date2.TZ);
   end ">=";

   package Date_Time_T_Comp is new Comparators (Date_Time_T);
   function "<" (Time1, Time2 : Date_Time_T)  return Boolean
     renames Date_Time_T_Comp."<";
   function "<=" (Time1, Time2 : Date_Time_T) return Boolean
     renames Date_Time_T_Comp."<=";
   function "=" (Time1, Time2 : Date_Time_T)  return Boolean
     renames Date_Time_T_Comp."=";
   function ">" (Time1, Time2 : Date_Time_T)  return Boolean
     renames Date_Time_T_Comp.">";
   function ">=" (Time1, Time2 : Date_Time_T) return Boolean
     renames Date_Time_T_Comp.">=";

   package Duration_T_Comp is new Comparators (Duration_T);
   function "<"  (Duration1, Duration2 : Duration_T) return Boolean
     renames Duration_T_Comp."<";
   function "<=" (Duration1, Duration2 : Duration_T) return Boolean
     renames Duration_T_Comp."<=";
   function "="  (Duration1, Duration2 : Duration_T) return Boolean
     renames Duration_T_Comp."=";
   function ">"  (Duration1, Duration2 : Duration_T) return Boolean
     renames Duration_T_Comp.">";
   function ">=" (Duration1, Duration2 : Duration_T) return Boolean
     renames Duration_T_Comp.">=";

end Schema.Date_Time;