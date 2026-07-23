from memory_ui import MemoryUI

mem_chat_hist = MemoryUI(user_id="default_user",agent_id="chat_history_agent")
mem_chat_hist.run()
user_pref = MemoryUI(user_id="default_user",agent_id="user_pref_agent")
user_pref.run()
mem_transcript = MemoryUI(user_id="default_user",agent_id="transcript_agent")
mem_transcript.run()

mem_chat_hist.add_memory("Teacher: How many stars are there in the American Flag? Student: 20 stars")
user_pref.add_memory("Jason is a secondary school student who loves playing games and watching basketball.")
mem_transcript.add_memory("""Okay, so we, we worked out that there is-
uh, a bound surface charge, and also if the polarization varies with position, um, there is also a bound volume charge density. Um, and then there is a surface current, uh, and a bound volume current density as well, uh, inside the material. Okay, and then we worked out-- So all that stuff was just-
exactly the same as for the situation, uh, in electrostatics and the magnetostatics. But for the time-varying case, we found that there is a, uh, time-varying, uh, polarization current as well, which is given by the time derivative of the polarization. Um, and then this satisfies a continuity equation, um, so that shows that in fact, it's necessary to include-
this polarization current, uh, or otherwise we would have a violation of conservation of charge. Um, but then if we look at the other situation for, um, this bound magnetization current, if we take its divergence, we see that it's always automatically zero, um, because the divergence of a curl of any vector is always zero, as long as it's well-behaved. Okay, um, so that, that means-
means that basically there, there's no corresponding, um, magnetization charge density, which is reasonable, of course. I mean, that, that kind of agrees with what we already knew, um, that there's, there's only electric charge, um, no such thing as magnetic charge. Okay. Um, all right, so let's, uh, now work with this. So, so we introduced, you know, these, uh-
""")

chat = mem_chat_hist.get_all_memories()
trans = mem_transcript.get_all_memories()
pref = user_pref.get_all_memories()

