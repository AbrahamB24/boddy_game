import 'package:supabase_flutter/supabase_flutter.dart';

const supabaseUrl = 'https://wyvgehzwpslbpibggmea.supabase.co';
const supabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Ind5dmdlaHp3cHNsYnBpYmdnbWVhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI2NjMzNzAsImV4cCI6MjA5ODIzOTM3MH0.1eBGfoI2jNOf7VQBNMmXPAe4Keqq7xb15KJxADDJqNc';

SupabaseClient get supabase => Supabase.instance.client;
